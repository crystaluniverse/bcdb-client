# bcdb-client

Rest client for [BCDB](https://github.com/threefoldtech/bcdb)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     bcdb:
       github: crystaluniverse/bcdb-client
   ```

2. Run `shards install`

## Usage

```crystal
require "bcdb"

c = Bcdb::Client.new unixsocket: "/tmp/bcdb.sock", db: "db", namespace: "example" 
tags = {"example" => "value", "tag2" => "v2"}
# PUT
key = c.put("a", tags)

# GET
res = c.get(key)
res["data"].should eq "a"
res["tags"]["example"].should eq "value"
res["tags"]["tag2"].should eq "v2"

# UPDATE
c.update(key, "b", tags)

res = c.get(key)
res["data"].should eq "b"
res["tags"]["example"].should eq "value"
res["tags"]["tag2"].should eq "v2"

# Delete
c.delete(key)
c.get(key)  =>  Bcdb::NotFoundError

# find
res = c.find({"example" => "value"})
puts res => [1,2,3] 
```
