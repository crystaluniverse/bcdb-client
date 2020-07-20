# bcdb-client

Rest client for [BCDB](https://github.com/threefoldtech/bcdb)

## Run tests
- `crystal spec spec/bcdb-client_spec.cr`

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     bcdb:
       github: crystaluniverse/bcdb-client
   ```

2. Run `shards install`

## Usage

##### Download, compile & run 0-db (Backend for BCDB)
- `git clone git@github.com:threefoldtech/0-db.git`
- `cd 0-db && make`
- `./zdb --mode seq`

##### Download, compile & run BCDB (Backend for BCDB)
- Install [Rust programming language](https://www.rust-lang.org/tools/install)
- `git clone git@github.com:threefoldtech/bcdb.git`
- `cd bcdb && make`
- copy bcdb binary anywhere `cp bcdb/target/x86_64-unknown-linux-musl/release/bcdb .`
- download `tfuser` utility from [here](https://github.com/crystaluniverse/bcdb-client/releases/download/v0.1/tfuser)
- use `tfuser` to register your 3bot user to explorer and generate seed file `usr.seed` using `./tfuser id create --name {3bot_username.3bot} --email {email}`
- run bcdb : `./bcdb --seed-file user.seed `
- now you can talk to `bcdb` through http via unix socket `/tmp/bcdb.sock`

##### Use the library in your application

**WARNING**

bcdb can have currently one database called `db` any attempt to use a different db name will fail, but you can freely use any `namespace` name you'd like

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
