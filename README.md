# Overview
This project contains scripts for comparing pgolto, bolt and propeller optimized mysqld.

# How to run
## 1. Prerequisite

- Download mysql-boost-8.0.29.tar.gz and place it under ```packages/``` directory
- clang / gcc toolchain preinstalled 
- git preinstalled
- sysbench preinstalled
- build [create_llvm_prof](https://github.com/google/autofdo) and copy it to the script directory.

## 2. Flavors of mysql binary
This scripts can build the following mysql binaries:
- vanilla - plain -O3 optimzied binary 
- vanillal - plain -O3 optimized with bolt instrumentation (-Wl,-q)
- vanillaq - plain -O3 optimized with propeller annotation (-fbasic-block-sections=labels)
- vanilla_bolt - -O3 + bolt optimized binary
- vanilla_propeller - -O3 + propeller optimized binary
- vanilla_propeller_int - -O3 + propeller_int optimized binary (internal only)
- pgolto - FDO and ThinLTO optimized binary
- pgoltol - FDO and ThinLTO optimized with bolt instrumentation (-Wl,-q) binary
- pgoltoq - FDO and ThinLTO optimized with propeller annotation (-fbasic-block-sections=labels) binary
- pgolto_bolt - FDO and ThinLTO and bolt optimized binary
- pgolto_propeller_int - FDO and ThinLTO and propeller optimized binary (internal only)

## 3 Build flavors

Use the following command to build a certain flavor:

> make \<flavor\>

For example:

> make vanilla pgolto_bolt

Will build 2 flavors of mysqld servers - vanilla and pgolto_bolt.

## 4 Run sysbench for flavors

Use the following command to run sysbench:

> make \<flavor\>-mysql/sysbench

For example

> make pgolto_propeller-mysql/sysbench

Will run sysbench for pgolto_propeller flavor.


## 5. Compare peformance

To compare performance:

> make \<A\>-vs-\<B\>

\<A\> and \<B\> are one of the above flavors. For example:

> make pgolto-vs-pgolto_propeller

compares performance between binaries optimized with pgolto and pgolto+propeller

## 6. **Note**

For external uses (not in google corp network), please open Makefile,
find the lines that define variable ```PROPELLER_INTRA_OPTS``` and
```PROPELLER_INTER_OPTS``` and set empty values to those two variables.

>PROPELLER_INTRA_OPTS :=
>
>PROPELLER_INTRA_OPTS :=

The above two options are only available for the internal create_llvm_prof.
