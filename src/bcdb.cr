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
    property unixsocket : String
    property size : Int32

    def initialize(@size, @unixsocket)
      (1..size).each do |i|
        self.create
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

    def create
      conn = Bcdb::Connection.new(UNIXSocket.new(@unixsocket))
      conn.id = UUID.random.to_s
      @connections[conn.id] = conn
      @free_connections << conn.id
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

    # Macro for reconnection 
    macro exec(*, method, path, headers, body)
        client = @pool.get
        
        3.times do |i|
          begin
            if {{body.id}}.nil?
              resp = client.{{method.id}} path: {{path.id}}, headers: {{headers.id}}
            else
              resp = client.{{method.id}} path: {{path}}, headers: {{headers}}, body: {{body}}
            end
            @pool.release client.id
            break
          rescue IO::Error
            if i == 3
              raise IO::Error.new "Connection lost"
            end
            pp! "connection Error. creating another connection"
            @pool.connections.delete(client.id)
            @pool.create
            client = @pool.get
          end
        end

    end

    def put(value : String, tags : Hash(String, String|Int32|Bool) = Hash(String, String|Int32|Bool).new)
      resp = nil
      exec method: post, path: @path, headers: HTTP::Headers{
             "X-Unix-Socket" => @unixsocket,
             "Content-Type" => "application/json",
             "x-tags" => tags.to_json
           },
           body: value 
      
      return resp.not_nil!.body.to_u64
    end

    def update(key : Int32|Int64|UInt64, value : String, tags : Hash(String, String|Int32|Bool) = Hash(String, String|Int32|Bool).new)
      resp = nil
      exec method: put, path: "#{@path}/#{key.to_s}",
           headers: HTTP::Headers{
             "X-Unix-Socket" => @unixsocket,
             "Content-Type" => "application/json",
             "x-tags" => tags.to_json
           }, body: value
      if  resp.not_nil!.status_code != 200  
          raise Bcdb::NotFoundError.new "not found"
        end
    end

    def get(key : Int32|Int64|UInt64)
      resp = nil
      exec method: get, path: "#{@path}/#{key.to_s}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}, body: nil
      if  resp.not_nil!.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
      tags = JSON.parse(resp.not_nil!.headers["x-tags"])
      {"data" => resp.not_nil!.body, "tags": tags}
    end

    # use key directly without namespace
    def fetch(key : Int32|Int64|UInt64)
      resp = nil
      exec method: get, path: "/#{@db}/#{key.to_s}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}, body: nil
      if  resp.not_nil!.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
      tags = JSON.parse(resp.not_nil!.headers["x-tags"])
      {"data" => resp.not_nil!.body, "tags": tags}
    end

    def delete(key : Int32|Int64|UInt64)
      resp = nil
      exec method: delete, path: "#{@path}/#{key.to_s}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}, body: nil
      if resp.not_nil!.status_code != 200
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
        
      3.times do |i|
        begin
          client.get path: "#{@path}?#{query}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"} do |response|
            c = 0 
            while gets = response.body_io.gets('\n', chomp: true)
                io = IO::Memory.new(gets)
                parser = JSON::Parser.new(io)
                item = parser.parse_one
                id =  item["id"].to_s
                ids << id.to_u64
                c += 1
              end
            end
          end

          @pool.release client.id
          return ids
        rescue IO::Error
          if i == 3
            raise IO::Error.new "Connection lost"
          end
          pp! "connection Error. creating another connection"
          @pool.connections.delete(client.id)
          @pool.create
          client = @pool.get
        end
      end
  end
end
