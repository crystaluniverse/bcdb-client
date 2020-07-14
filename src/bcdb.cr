require "json"
require "socket"
require "http/client"

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
  class Client
    property unixsocket : String
    property db : String
    property namespace : String
    property path : String

    def initialize(@unixsocket, @db, @namespace)
      @path = "/#{@db}/#{@namespace}"
      @socket = UNIXSocket.new(@unixsocket)
      @client = HTTP::Client.new(@socket)
    end

    def put(value : String, tags : Hash(String, String|Int32|Bool) = Hash(String, String|Int32|Bool).new)
      
        resp = @client.post @path, headers: HTTP::Headers{
             "X-Unix-Socket" => @unixsocket,
             "Content-Type" => "application/json",
             "x-tags" => tags.to_json
           },
           body: value
        
        resp.body.to_u64
    end

    def update(key : Int32|Int64|UInt64, value : String, tags : Hash(String, String|Int32|Bool) = Hash(String, String|Int32|Bool).new)
      resp = @client.put "#{@path}/#{key.to_s}",
           headers: HTTP::Headers{
             "X-Unix-Socket" => @unixsocket,
             "Content-Type" => "application/json",
             "x-tags" => tags.to_json
           }, body: value
       
      if resp.status_code != 200  
          raise Bcdb::NotFoundError.new "not found"
        end
    end

    def get(key : Int32|Int64|UInt64)
      resp = @client.get "#{@path}/#{key.to_s}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}
      if resp.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
      tags = JSON.parse(resp.headers["x-tags"])
      {"data" => resp.body, "tags": tags}
    end

    # use key directly without namespace
    def fetch(key : Int32|Int64|UInt64)
      resp = @client.get "/#{@db}/#{key.to_s}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}
      if resp.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
      tags = JSON.parse(resp.headers["x-tags"])
      {"data" => resp.body, "tags": tags}
    end

    def delete(key : Int32|Int64|UInt64)
      resp = @client.delete "#{@path}/#{key.to_s}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}
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
      @client.get "#{@path}?#{query}", headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"} do |response|
      c = 0  
      while gets = response.body_io.gets('\r', chomp: false)
          io = IO::Memory.new(gets)
          parser = JSON::Parser.new(io)
          # while io.pos != io.size
          #   item = parser.parse_one
          #   id =  item["id"].to_s
          #   ids << id.to_u64
          # end
          item = parser.parse_one
          id =  item["id"].to_s
          ids << id.to_u64
          c += 1
        end
      end
      ids
    end
  end
end
