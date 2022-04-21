# Running iob-cache in Mayhem

ForAllSecure's Mayhem can help companies achieve code coverage in Verilog.
Verilog is used in chip design, and companies need to extensively test every
line of code before burning to silicon. However, it is incredibly expensive to
manually write tests. Mayhem can help automatically achieve code coverage,
lowering the total cost to verify Verilog designs and speeding up time to
production.

This repo is a fork that has a specific challenge created by a commercial
company interested in seeing what Mayhem could do. We were given the Open Source
[iob-cache](https://github.com/IObundle/iob-cache) written in Verilog with
modifications to insert "corner cases". Mayhem's goal was to create test vectors
for those corner cases.

This document is divided into three sections:
  1. A quick start, which will allow you to reproduce our results using an
     existing [Docker image](https://hub.docker.com/repository/docker/dbrumley/iob-cache).
  2. A guide to building from scratch, including creating a docker image and
     pushing to a registry.
  3. A more comprehensive walk-through discussing the particulars of getting the
     Verilog running in Mayhem. 

## Quick Start

We've set up a branch that has everything ready to go to analyze with
Mayhem.

Pre-requisites: You have an account on a Mayhem server.

Steps to run:
  1. Log into your Mayhem server.
  2. Click the "+" symbol in the upper left side of the screen.
  3. Choose "From Docker Hub" tab.
  4. Enter "dbrumley/iob-cache". See below if you'd like to build the image
     yourself from scratch.
  5. In the "Edit Mayhemfile", in the bottom you will see green text on black
     background. Append "@@" to the end of the line, so the full line reads
     `/iob-cache/hardware/simulation/verilator/obj_dir/Viob_cache @@`.  The `@@`
     says the program will take an input file passed as `argv[1]`. 
  6. Click start run
  
Mayhem will immediately start exploring the program, and will generate test
vectors that increase coverage. It will take around 160k CPU seconds to generate
the first test vector that hits a challenge "corner case", or about 6 clock
hours with an 8-core Mayhem worker node.  

## Building from scratch

This section describes how to build the docker image from scratch, push it to a
private Mayhem registry server, and run it under Mayhem.

Pre-requisites:
  * You have a UNIX command line with git, docker, and the Mayhem CLI
  installed. 
  * You've already logged into your Mayhem server.
  * We refer to your Mayhem username as <username>.

First, check out *recursively* our fork of iob-cache with our `mayhem`
branch. Nothing will build if you do not clone recursively!
```
# Remember to use --recursive!
git clone --recursive git@github.com:dbrumley/iob-cache.git

# Switch to the branch with all the code necessary to test in Mayhem
git checkout mayhem
```

Second, build the docker image tagged with the full path to your
Mayhem docker registry, and push to the registry:
```
# mayhem docker-registry will return the name of your private Mayhem
# docker registry for commercial customers.
# 
# Free users will need to tag and push to a public repository, such as 
# Dockerhub or Github's ghcr.io registry.
docker build -t $(mayhem docker-registry)/<username>/iob-cache
docker push $(mayhem docker-registry)/<username>/iob-cache
```

Third, edit the Mayhemfile `baseimage` variable to point to the full
URL for the docker image you just pushed:
```
# Put the full path to your docker image. 
# $MAYHEM_DOCKER_REGISTRY points to your currently logged in Mayhem registry
# Change to the full path if using a public repository.

baseimage: $MAYHEM_DOCKER_REGISTRY/<username>/iob-cache:latest
```

At this point, you can either use the UI above to start a Mayhem run, or launch
it on the CLI from the root of the `iob-cache` git repo with:
```
mayhem run .
```

Again, it will take 5-6 hours to create a test vector for the first corner case.

We have manually added four test vectors (`answer-cafecafe`, `answer-deadbeef`,
`answer-f1e2d3c4`, and `answer-01020304`) to test whether your build worked.To
run them:

```
# Run the docker container locally in interactive mode
docker run -ti $(mayhem docker-registry)/<username>/iob-cache bash
root@2ed81393d4ad:/iob-cache# /iob-cache/hardware/simulation/verilator/obj_dir/Viob_cache answer-01020304 
```

## In-depth Walk Through

In this section, we walk through the details on how we integrated `iob-cache` to
use Mayhem.  At a high level, we:

  1. Cloned `iob-cache` from upstream. 
  2. Apply the patches to `iob-cache` to create the "Challenge" problem. The
     patches were provided by a company interested in using Mayhem. In addition,
     we modified `testharness.cpp` to read in test vectors from a file. 
  3. Compile `iob-cache` with the integer-splitting optimization. While
     technically optional, in practice this is used because it speeds up
     analysis several-fold. 
  4. Add `assert` statements to notify you when the challenges are solved.
     Mayhem does not typically tell you when particular lines of code are hit
     (it's growing coverage). This (generic) technique will tell Mayhem
     something "interesting" has happened beyond just growing coverage. It's a
     useful, especially in the context of the Verilog challenge we were given. 
  5. Dockerized the app by writing a `Dockerfile`.
  6. Write a `Mayhemfile` to specify how Mayhem should perform analysis.
  7. (Optional): Create an initial (random) input test vector. 
  8. Initiate a run.
  
We've also written a script [build.sh](./build.sh) which performs steps 2-4 on
the code base.

### Background: Integer Splitting Optimization

The challenge we were given uses very specific integer constants to trigger
particular code branches. To speed up analysis, we will be building iob-cache
using `afl-clang` to take advantage of an integer splitting optimization. This
is purely an optimization, but does speed up time to find the corner cases. 

Note that while we use integer splitting to generate the test suite, you can
always *replay* the test suite under a compiled version without integer
splitting if you are concerned about any changes in behavior. Therefore, you do
not need to worry about integer split version used for generating tests to
somehow not be faithful to the production code. 

Integer splitting is an optimization to speed up finding inputs that satisfy
comparisons.  It works by turning a word-size comparison into multiple
byte-length comparisons. For example, suppose the original code contains a
word-size comparison with `0xabad1dea`:

```
if(input == 0xabad1dea) {
  /* bug */
}
```

The probability of picking 0xabad1dea is 2^{-32}. Integer splitting rewrites the
code to the semantically equivalent byte-length comparisons:

```
if(input >> 24 == 0xab)
  if(input & 0xff0000) >> 16 == 0xad)
     if(input & 0xff00) >> 8 == 0x1d)
        if(input & 0xff) == 0xea)
	  /* bug */
```

Integer splitting reduces the probability for heuristic-guided search to
4*2^{-8} = 2^{-10}, which is much less than 2^{-32}. 

We use an [LLVM pass](https://gitlab.com/laf-intel/laf-llvm-pass/) that is
easily integrated into the existing compile toolchain using the 
[AFL drivers](https://github.com/AFLplusplus/AFLplusplus/blob/stable/instrumentation/README.laf-intel.md)
to add integer splitting.


### Step 1: Clone the `iob-cache` repository

First, we cloned the `iob-cache` github repository. It's important to make sure
you clone recursively, else nothing will build properly!

```
# Check out recursively or nothing will work!
git clone --recursive git@github.com:IObundle/iob-cache.git

# Check out the mayhem branch to follow along.
git checkout mayhem
```

All changes to the master code base are kept as `testbench.patch` and
`verilog.patch`. We included these to make it easy to see our changes. (We know
in real development, you'd just check the changes directly into the git branch
and not keep separate patch files. These are kept separately for illustrative
purposes.) We will go through these changes, and files added, below.

### Step 2: Apply the patches to `iob-cache` to create the challenge

A commercial company created a set of challenge states to hit by modifying two
files:
  * `hardware/src/front-end.v`
  * `hardware/src/iob-cache.v`
  
The changes are summarized in [verilog.patch](./verilog.patch). These patches
are applied as part of `build.sh`, and can be manually applied with:

```
patch -p1 < verilog.patch
```

Mayhem creates test vectors as files, and we call the set of test vectors the
"test suite" or "corpus".  Mayhem can automatically create test files for any
program that reads from TCP, UDP, stdin, or a file.  `iob-cache`, however, does
not read in from a file by default.

We modified `hardware/simulation/verilator/testbench.cpp`  to read in tests to
check from a file. The changes are automatically applied in the `build.sh`
script, or can manually be applied with:

```
patch -p1 < testbench.patch
```

### Step 3: Compile `iob-cache` with integer splitting

We use [AFL](https://aflplus.plus/) to perform integer splitting and add some
helpful instrumentation to the program binary.  Mayhem itself runs a portfolio
of dynamic analysis, and can work without this instrumentation. However, when
source is available, we recommend using compile-in instrumentation because it
will increase performance.

The `iob-cache` code base uses typical `make` environment variables to set the
compiler and flags. We first set the environment variable `AFL_LLVM_LAF_ALL`,
which directs the compiler to perform integer splitting, and then call `make`
with the proper arguments:

```
make sim SIMULATOR=verilator CC=afl-clang CXX=afl-clang++ \
LINK=afl-clang ++ CFLAGS="-O2 -ggdb" CXXFLAGS="-O2 -ggdb" LDFLAGS="-O2 -ggdb"
```

Again, this is all automatically done in the `build.sh` script.


### Step 4: Add `assert` statements

Mayhem automatically runs and grows code coverage. It does not currently have a
feature, however, to notify a user when a test vector hits a particular line of
code. Instead of creating a custom feature, Mayhem will notify the user any time
a newly generated test vector violates an `assert` statement. (More
technically, a signal is raised from the process, in this case SIGABRT). This
approach gave us a language-neutral way of supporting arbitrary user-defined
cases.


One complexity here is `iob-cache` takes a verilog file and *generates* C++ code
with `verilator`.  We need the `assert` inside the "verilated" C++ code.  For
demo purposes, we simply added the `assert` statements after `verilator` is run,
and re-compile.

Instead of a larger change of `Makefile`, we include a small script
[add-assertion.sh](./add-assertion.sh) which replaces the correct file and
re-links the final executable.  You do not need to do this manually; it's
automatically done in `build.sh`.


### Step 5: Dockerize the App

Mayhem performs dynamic analysis, and we use Docker as a lightweight tool to
give Mayhem the full runtime and configuration environment.  Docker is extremely
common in DevOps and DevSecOps pipelines.  `iob-cache`, however, did not have a
`Dockerfile`.  

We wrote a small [Dockerfile](./Dockerfile) that builds the application and
calls `build.sh`. Here are the contents:

```
FROM debian:bullseye-slim
RUN apt-get update && \
  apt-get install -y build-essential clang afl vim gdb libc6-dbg verilog \
  verilator less
COPY corpus /corpus
WORKDIR /iob-cache
COPY . .
RUN ./build.sh
CMD ["/iob-cache/hardware/simulation/verilator/obj_dir/Viob_cache"]
```

If you've not already done so, please log into your Mayhem server. Mayhem has an
extensive CLI to improve productivity and easily integrate into CI/CD and
scripts. You first need to download the `mayhem` CLI from your Mayhem server,
and then run `mayhem login <server> <token>` to log in. Please see the
documentation to learn more about `mayhem login` and generating a CLI token.


As described in the "quick build" section, the docker image can be recreated and
pushed to a Mayhem registry with:
```
# mayhem docker-registry will return the name of your private Mayhem
# docker registry for commercial customers.
# 
# Free users will need to tag and push to a public repository, such as 
# Dockerhub or Github's ghcr.io registry.
docker build -t $(mayhem docker-registry)/<username>/iob-cache
docker push $(mayhem docker-registry)/<username>/iob-cache
```

```
```


### Step 6: Write a `Mayhemfile`

Mayhem uses configuration-as-code with a `Mayhemfile`.  If you performed the
quick start above, the UI will automatically generate a `Mayhemfile` for you,
which can then be checked into git.

We wrote a `Mayhemfile` to show how you can ingrate Mayhem from the UNIX command
prompt, and thus how to integrate into any DevOps pipeline.  

We show below the `Mayhemfile`, and what each statement means.

```
# The Mayhem version you are writing this configuration for.
version: '1.16'

# Change baseimage to be the same as your push URL above. 
# You can use $MAYHEM_DOCKER_REGISTRY as shorthand for the name of the 
# registry, e.g., $MAYHEM_DOCKER_REGISTRY/dbrumley/iob-cache:latest points
# to an image on your local registry.  If you forget the name, you can find it
# with the $(mayhem docker-registry) command.
baseimage: dbrumley/iob-cache:latest

# The project name in the UI. A common convention is the git project name
project: dbrumley/iob-cache

# A unique name in the UI for this particular target app.  A project
# (e.g., git repo) can have multiple targets, each specified in their
# own Mayhemfile
target: iob-cache

# Mayhem can perform a variety of tasks, such as regression testing,
# measuring code coverage, and so on.  This line says to only run
# the primary Mayhem analysis.
tasks:
  - name: behavior_testing
  
# The executable command to run within the Docker image. This is the executable
# to test.  The "@@" says the input file name is given as argv[1].
# Mayhem will generate a file, and substitute the filename every where it
# sees an "@@".
cmds:
  - cmd: /iob-cache/hardware/simulation/verilator/obj_dir/Viob_cache @@
```


### Step 7: (optional) Create an initial (random) input test vector

Mayhem can start with your existing test suite and grow it. We call the initial
set of test vectors the "seed set". The initial seed set is placed in a `corpus`
directory, which `mayhem run` (next step) will read.

For this challenge, we had no test cases, so we generated one randomly chosen
seed (via `dd if=/dev/random of=corpus/seed bs=8 count=2`). 


### Step 8: Run Mayhem from the CLI

Again, if you've not already downloaded the `mayhem` CLI and logged in, please
do that first.

Once you are logged in, you can run this example with:
```
mayhem run .
```

Mayhem will start exploring the state space of the app, and generating test
vectors. The test vectors can be downloaded at any time via the web UI, or also
via the CLI with `mayhem sync`. We post new test vectors live as they are
discovered. In our tests, it took 5-6 hours to create the first test vector for
one of the challenge states.


# Questions?

If you have any questions, please email support@forallsecure.com.
