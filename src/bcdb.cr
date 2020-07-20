require "json"
require "uuid"
require "socket"
require "http/client"
require "./errors"

class Bcdb::NotFoundError < Exception 
  def initialize (@err : String); end
end


class Bcdb::Result
  include JSON::Serializable

  property id : String = ""

  def initialize; end
end

# Monkey patch to allow using unix socket directly
class HTTP::Client
  @socket : IO?
  @reconnect = true
  def initialize(@socket : IO, @host = "", @port = 80)
    @reconnect = false
  end
  private def socket
    socket = @socket
    return socket if socket
    unless @reconnect
      raise "This HTTP::Client cannot be reconnected"
    end
    previous_def
  end
end

class JSON::Parser
  # JSON parse_value is private. We can make a public alias of that method
  # that will return the JSON::Any parsed value without checking that EOF
  # is reached after it. See `JSON::Parser#parse`.
  def parse_one : Any
    parse_value
  end
end


module Bcdb
  class Connection < HTTP::Client
    property id : String = ""
  end

  class Connectionpool
      property connections : Hash(String, Bcdb::Connection) = Hash(String, Bcdb::Connection).new
      property free_connections : Array(String) = Array(String).new

      def initialize(size, unixsocket)
        (1..size).each do |i|
          conn = Bcdb::Connection.new(UNIXSocket.new(unixsocket))
          conn.id = UUID.random.to_s
          @connections[conn.id] = conn
          @free_connections << conn.id
        end
      end

      def get
        raise Bcdb::NoFreeConnectionsError.new if @free_connections.size == 0
        id = @free_connections.pop
        @connections[id]
      end

      def release(id)
        @free_connections << id
      end

      def free
        @free_connections.size
      end

      
  end

  class Client
    property unixsocket : String
    property db : String
    property namespace : String
    property path : String
    property pool_size : Int32
    property pool : Bcdb::Connectionpool

    def initialize(@unixsocket, @db, @namespace, @pool_size=20)
      @path = "/#{@db}/#{@namespace}"
      @pool = Bcdb::Connectionpool.new @pool_size, @unixsocket
    end

    def put(value : String, tags : Hash(String, String|Int32|Bool) = Hash(String, String|Int32|Bool).new)
        client = @pool.get
        resp = client.post @path, headers: HTTP::Headers{
             "X-Unix-Socket" => @unixsocket,
             "Content-Type" => "application/json",
             "x-tags" => tags.to_json
           },
           body: value
        @pool.release client.id
        resp.body.to_u64
    end

    def update(key : Int32|Int64|UInt64, value : String, tags : Hash(String, String|Int32|Bool) = Hash(String, String|Int32|Bool).new)
      client = @pool.get
      resp = client.put "#{@path}/#{key.to_s}",
           headers: HTTP::Headers{
             "X-Unix-Socket" => @unixsocket,
             "Content-Type" => "application/json",
             "x-tags" => tags.to_json
           }, body: value
      @pool.release client.id
      if resp.status_code != 200  
          raise Bcdb::NotFoundError.new "not found"
        end
    end

    def get(key : Int32|Int64|UInt64)
      client = @pool.get
      resp = client.get "#{@path}/#{key.to_s}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}
      @pool.release client.id
      if resp.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
      tags = JSON.parse(resp.headers["x-tags"])
      {"data" => resp.body, "tags": tags}
    end

    # use key directly without namespace
    def fetch(key : Int32|Int64|UInt64)
      client = @pool.get
      resp = client.get "/#{@db}/#{key.to_s}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}
      @pool.release client.id
      if resp.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
      tags = JSON.parse(resp.headers["x-tags"])
      {"data" => resp.body, "tags": tags}
    end

    def delete(key : Int32|Int64|UInt64)
      client = @pool.get
      resp = client.delete "#{@path}/#{key.to_s}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}
      @pool.release client.id
      if resp.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
    end
  
    def find(tags : Hash(String, String))
      query = ""
      
      tags.each_key do |k|
        query += "#{k}=#{tags[k]}&"
      end
      
      query.rstrip "&"

      ids = []of UInt64
      client = @pool.get
      client.get "#{@path}?#{query}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"} do |response|
      c = 0  
      while gets = response.body_io.gets('\r', chomp: false)
          io = IO::Memory.new(gets)
          parser = JSON::Parser.new(io)
          item = parser.parse_one
          id =  item["id"].to_s
          ids << id.to_u64
          c += 1
        end
      end
      @pool.release client.id
      ids
    end
  end
end
