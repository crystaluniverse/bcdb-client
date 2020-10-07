require "json"
require "uuid"
require "socket"
require "http/client"
require "./errors"

class Bcdb::Result
  include JSON::Serializable

  property id : String = ""

  def initialize; end
end

class Bcdb::AclItem
  include JSON::Serializable

  property permission : String = ""
  property users : Array(Int32) = [] of Int32

  def initialize; end
end

class Bcdb::AclResult
  include JSON::Serializable

  property id : Int32 = 0
  property acl : Bcdb::AclItem = Bcdb::AclItem.new

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

  class ClientParent
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
  end

  class Acl < ClientParent
    property pool : Bcdb::Connectionpool
    property path : String
    property unixsocket : String

    def initialize(@unixsocket, @pool, @path); end

    def set(permission : String, users : Array(Int32))
      resp = nil
      exec method: post, path: @path, headers: HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
      },
        body: {"perm" => permission, "users" => users}.to_json
      return resp.not_nil!.body.to_u64
    end

    def get(key : Int32 | Int64 | UInt64)
      resp = nil
      exec method: get, path: "#{@path}/#{key.to_s}", headers: HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
      },
        body: nil

      if resp.not_nil!.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end

      body = JSON.parse(resp.not_nil!.body)
      users = [] of Int32
      body["users"].as_a.each do |u|
        users << u.to_s.to_i32
      end
      {"permission" => body["perm"].to_s, "users": users}
    end

    def list
    end

    # Update permission in ACl/Group
    def update(key : Int32 | Int64 | UInt64, permission : String)
      resp = nil
      exec method: put, path: "#{@path}/#{key.to_s}", headers: HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
      },
        body: {"perm" => permission}.to_json
    end

    # Add users to ACl/Group
    def grant(key : Int32 | Int64 | UInt64, users : Array(Int32))
      resp = nil
      exec method: post, path: "#{@path}/#{key.to_s}/grant", headers: HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
      },
        body: {"users" => users}.to_json
    end

    # Remove users from ACl/Group
    def revoke(key : Int32 | Int64 | UInt64, users : Array(Int32))
      resp = nil
      exec method: post, path: "#{@path}/#{key.to_s}/revoke", headers: HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
      },
        body: {"users" => users}.to_json
    end

    # list acl
    def list
      result = Array(Hash(String, Int32 | String | Array(Int32))).new

      client = @pool.get

      3.times do |i|
        begin
          client.get path: @path, headers: HTTP::Headers{"X-Unix-Socket" => @unixsocket, "Content-Type" => "application/json"} do |response|
            c = 0
            while gets = response.body_io.gets('\n', chomp: true)
              io = IO::Memory.new(gets)
              parser = JSON::Parser.new(io)
              item = parser.parse_one
              res = {"id" => item["key"].to_s.to_i32, "permission" => item["acl"]["perm"].to_s, "users" => [] of Int32}

              item["acl"]["users"].as_a.each do |i|
                res["users"].as(Array(Int32)) << i.to_s.to_i32
              end
              result << res
              c += 1
            end
          end
        end

        @pool.release client.id
        return result
      rescue IO::Error
        pp! "connection Error. creating another connection"
        @pool.connections.delete(client.id)
        @pool.create
        client = @pool.get
      end
      raise IO::Error.new "Connection lost"
    end
  end

  class Client < ClientParent
    property unixsocket : String
    property db : String
    property namespace : String
    property path : String
    property pool_size : Int32
    property pool : Bcdb::Connectionpool
    property acl : Acl

    def initialize(@unixsocket, @db, @namespace, @pool_size = 20)
      @db = "db"
      @path = "/#{@db}/#{@namespace}"
      @pool = Bcdb::Connectionpool.new @pool_size, @unixsocket
      @acl = Acl.new unixsocket: unixsocket, path: "/acl", pool: pool
    end

    def put(value : String, tags : Hash(String, String | Int32 | Bool) = Hash(String, String | Int32 | Bool).new, threebot_id : String = "", acl : UInt64 = 0)
      resp = nil

      headers = HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
        "x-tags"        => tags.to_json,
      }

      if threebot_id != ""
        headers["x-threebot-id"] = threebot_id
      end

      if acl != 0_u64
        headers["x-acl"] = acl.to_s
      end

      exec method: post, path: @path, headers: headers, body: value
      return resp.not_nil!.body.to_u64
    end

    def update(key : Int32 | Int64 | UInt64, value : String, tags : Hash(String, String | Int32 | Bool) = Hash(String, String | Int32 | Bool).new, threebot_id : String = "")
      resp = nil
      headers = HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
        "x-tags"        => tags.to_json,
      }

      if threebot_id != ""
        headers["x-threebot-id"] = threebot_id
      end

      exec method: put, path: "#{@path}/#{key.to_s}", headers: headers, body: value
      if resp.not_nil!.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
    end

    def get(key : Int32 | Int64 | UInt64, threebot_id : String = "")
      resp = nil
      headers = HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
      }

      if threebot_id != ""
        headers["x-threebot-id"] = threebot_id
      end

      exec method: get, path: "#{@path}/#{key.to_s}", headers: headers, body: nil
      if resp.not_nil!.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
      tags = JSON.parse(resp.not_nil!.headers["x-tags"])
      {"data" => resp.not_nil!.body, "tags": tags}
    end

    # use key directly without namespace
    def fetch(key : Int32 | Int64 | UInt64, threebot_id : String = "")
      resp = nil
      headers = HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
      }

      if threebot_id != ""
        headers["x-threebot-id"] = threebot_id
      end

      exec method: get, path: "/#{@db}/#{key.to_s}", headers: headers, body: nil
      if resp.not_nil!.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
      tags = JSON.parse(resp.not_nil!.headers["x-tags"])
      {"data" => resp.not_nil!.body, "tags": tags}
    end

    def delete(key : Int32 | Int64 | UInt64, threebot_id : String = "")
      resp = nil

      headers = HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
      }

      if threebot_id != ""
        headers["x-threebot-id"] = threebot_id
      end

      exec method: delete, path: "#{@path}/#{key.to_s}", headers: headers, body: nil
      if resp.not_nil!.status_code != 200
        raise Bcdb::NotFoundError.new "not found"
      end
    end

    def find(tags : Hash(String, String), threebot_id : String = "")
      query = ""

      tags.each_key do |k|
        query += "#{k}=#{tags[k]}&"
      end

      query.rstrip "&"

      ids = [] of UInt64

      client = @pool.get

      headers = HTTP::Headers{
        "X-Unix-Socket" => @unixsocket,
        "Content-Type"  => "application/json",
      }

      if threebot_id != ""
        headers["x-threebot-id"] = threebot_id
      end

      3.times do |i|
        begin
          client.get path: "#{@path}?#{query}", headers: headers do |response|
            c = 0
            while gets = response.body_io.gets('\n', chomp: true)
              io = IO::Memory.new(gets)
              parser = JSON::Parser.new(io)
              item = parser.parse_one
              id = item["id"].to_s
              ids << id.to_u64
              c += 1
            end
          end
        end

        @pool.release client.id
        return ids
      rescue IO::Error
        pp! "connection Error. creating another connection"
        @pool.connections.delete(client.id)
        @pool.create
        client = @pool.get
      end
      raise IO::Error.new "Connection lost"
    end
  end
end
