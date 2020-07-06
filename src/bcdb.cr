require "json"
require "socket"
require "http/client"

class Bcdb::NotFoundError < Exception 
  def initialize (@err : String); end
end

module Bcdb 
  class Client
    property unixsocket : String
    property db : String
    property namespace : String
    property path : String

    def initialize(@unixsocket, @db, @namespace)
      @path = "/#{@db}/#{@namespace}"
    end

    def put(value : String, tags : Hash(String, String|Int32|Bool) = Hash(String, String|Int32|Bool).new)
      UNIXSocket.open(@unixsocket) do |io|
        request = HTTP::Request.new(
          "POST",
           @path,
           headers: HTTP::Headers{
             "X-Unix-Socket" => @unixsocket,
             "Content-Type" => "application/json",
             "x-tags" => tags.to_json
           }, body: value
        )
        request.to_io(io)
        resp = HTTP::Client::Response.from_io(io).body
        resp.to_u64
      end
    end

    def update(key : Int32|Int64|UInt64, value : String, tags : Hash(String, String|Int32|Bool) = Hash(String, String|Int32|Bool).new)
      UNIXSocket.open(@unixsocket) do |io|
        request = HTTP::Request.new(
          "PUT",
          "#{@path}/#{key.to_s}",
           headers: HTTP::Headers{
             "X-Unix-Socket" => @unixsocket,
             "Content-Type" => "application/json",
             "x-tags" => tags.to_json
           }, body: value
        )
        request.to_io(io)
        res = HTTP::Client::Response.from_io(io)
        if res.status_code != 200
          raise Bcdb::NotFoundError.new "not found"
        end
      end
    end

    def get(key : Int32|Int64|UInt64)
      UNIXSocket.open(@unixsocket) do |io|
        request = HTTP::Request.new(
          "GET",
           "#{@path}/#{key.to_s}",
           headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"}
        )
        request.to_io(io)
        res = HTTP::Client::Response.from_io(io)
        if res.status_code != 200
          raise Bcdb::NotFoundError.new "not found"
        end
        tags = JSON.parse(res.headers["x-tags"])
        {"data" => res.body, "tags": tags}
      end
    end
  end
end
