require "./spec_helper"
require "json"

describe Bcdb::Client do
  it "works" do
    seed_phrase = %(finger feel food anchor morning benefit stable gesture kiwi tortoise amount glide deputy cake party few canyon title effort gentle route tape gallery over)
    threebot_id = 40
    
    c = Bcdb::Client.new("http://127.0.0.1:50061/db/koko", threebot_id, seed_phrase)
    key = c.put("a", {"a" => "a", "b" => "b"}.to_json)
    c.get(key).should eq({"a" => "a", "b" => "b"}.to_json)
  end
end
