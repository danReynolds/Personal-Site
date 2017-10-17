---
layout: post
title: Upgrading Yarn, or Maybe Going Back to NPM
image: '/images/tech/chrome.png'
category: Tech
tags: [project, yarn, javascript]
---

Yarn 1.0 has been out for a while now and in the process of upgrading from version 0.27.5 to 1.2.1 I've decided to
re-familiarize myself with Yarn and what makes it different from NPM.

<!--halt-->

# How We Use It

We Have been using Yarn for a while on our project, but overall I've found it to be pretty interchangable with npm besides the fact that by default
it uses a lockfile.

Overall some of our teams have kept using npm, some use yarn for its default lock file, and some use it without a lock file. This has led
me to the conclusion that most people aren't too opinionated on the version manager we use either way and I wanted to take a brief look
into some of the different features and implementations of each option.

# The Case for Yarn

The benefits I heard about Yarn when it came out was that it is generally faster than NPM and uses a lock file to ensure that you end up getting deterministic dependencies.

In terms of speed, Yarn downloads dependencies in parallel and stores them in a global cache that makes repeat installs really fast. That's awesome and Yarn's install speed is one of the big
reasons I've heard for using it over NPM.

Looking into it though, I found that NPM has its own cache which stores all http request data that npm fetches [4] https://docs.npmjs.com/cli/cache and that you can just enable it by setting the flag `prefer-offline`,
in your npm config, usually in `~/.npmrc` [5] https://docs.npmjs.com/misc/config. With this flag NPM will favor using cached packages and only fetch it from the online repositories when there is a cache miss.

I wanted to test install speeds on our React Native project to get an idea about their performance differences and ran both Yarn and NPM installations with and without their respective caches, yielding
the following results:


| Tool          | Uncached Time   | Cached Time  |
| ------------- |:---------------:| ------------:|
| Yarn 1.2.1    | 437.24s         | 108.11s      |
| NPM  3.10.10  | 279.57s         | 204.94s      |

Yarn definitely performs faster when cached, but is much slower on an uncached install compared to NPM. Since most of the time you should have the global cache, I'll give this one to Yarn.

The other big difference between yarn was that it by default provided the `yarn.lock` file, a system similar to cargo or bundler that would install a defined
version of dependencies and offer repeatable installations.

NPM has had support for version locked dependencies using the `npm shrinkwrap` command for years, which generates a `npm-shrinkwrap.json`
with dependency versions based on what is currently installed under the `node_modules` folder [2] https://nodejs.org/en/blog/npm/managing-node-js-dependencies-with-shrinkwrap/.

Yarn describes its locking mechanism as similar to shrinkwrap, with the addition that it is fully automatic and that it's *it’s not lossy and it creates reproducible results* [3] https://yarnpkg.com/en/docs/yarn-lock.

I wasn't exactly sure what that means so I looked around, there is actually a issue recently opened on Yarn for (exact question)[https://github.com/yarnpkg/website/issues/509]. The accepted answer returned from
a search on Google is (here)[https://stackoverflow.com/questions/40057469/what-is-the-difference-between-yarn-lock-and-npm-shrinkwrap/40057535#40057535] and talks about how npm-shrinkwrap can lead to non-deterministic results.

This seems at odds with the purpose of shrinkwrap, which claimed the following when introduced [6] https://nodejs.org/en/blog/npm/managing-node-js-dependencies-with-shrinkwrap/

> When "npm install" installs a package with a npm-shrinkwrap.json file in the package root, the shrinkwrap file (rather than package.json files) completely drives the installation of that package and all of its dependencies (recursively).

I believe that the difference is that shrinkwrap only locks down your dependency versions, but not actually the contents of the dependencies, allowing authors to force updates to their libraries or re-publish
their libraries. NPM recommends the following [7] https://www.alexkras.com/understanding-differences-between-npm-yarn-and-pnpm/:

> If you wish to lock down the specific bytes included in a package, for example to have 100% confidence in being able to reproduce a deployment or build, then you ought to check your dependencies into source control, or pursue some other mechanism that can verify contents rather than versions.

Yarn on the other hand makes it clear that it uses checksums to determine the integrity of every piece of code you download. You can run this yourself with the `yarn check --integrity` command [8] https://yarnpkg.com/en/.

Based on the speed and integrity differences between NPM and Yarn it looks like it was definitely a valuable addition to the lives of JavaScript developers.

# Where NPM is Today

As I look to upgrade our version of Yarn I wanted to check the current state of NPM to determine if Yarn still makes a compelling argument for first-class performance and stability through deterministic dependency management.

NPM launched version [5.0](http://blog.npmjs.org/post/161081169345/v500) earlier this year and with it come some nice improvements, two in particular stand out. For one, NPM now uses a standardized, deterministic lockfile implementation called a `package-lock.json` which will be automatically created when packages are installed unless an `npm-shrinkwrap.json` already exists and takes precedence if they both do. It also verifies packages against tarballs in the cache to ensure integrity.

It looks like NPM heard the community's enthusiasm for Yarn's lockfiles loud and clear.

Both Yarn and NPM 5 now support deterministic lockfiles, with some interesting differences described by Yarn [here](https://yarnpkg.com/blog/2017/05/31/determinism/).

Yarn guarantees deterministic lockfiles **only** across the same version of Yarn. `yarn.lock` files are flat and do not have any information on the hoisting and position of top level dependencies. Yarn internally determines the positioning of packages to go in the node_modules, meaning that the result could vary with different Yarn versions. The primary benefit of this approach is that the yarn.lock file is very easy to diff and resolve merge conflicts with than a  nested JSON structure.

Alternatively, NPM 5 uses a JSON lockfile that already has its dependencies hoisted in the exact position that they are structured in the node_modules folder, meaning that two developers could use the same lockfile and produce the same directory structure.

This led Yarn to make the following statement:

> npm 5 has stronger guarantees across versions and has a stronger deterministic lockfile, but Yarn only has those guarantees when you’re on the same version in favor of a lighter lockfile that is better for review. It’s possible that there’s a lockfile solution that has the best of both worlds, but for now this is current state of the ecosystem and possible convergence could happen in the future.

That's pretty cool that they're open to combining the systems in the future.

NPM 5 also had it's cache implementation rewritten and while they humbly hope that it has made things faster, the link they provided [here](https://twitter.com/maybekatz/status/865393382260056064) has me excited about giving it a try. The previous performance tests above were run against our current NPM version of 3.10.10, but let's see if bumping that to 5.5.1 gives us a strong improvement.

Using the latest npm version gave the following results (both NPM 5.1.1 and Yarn 1.2.1 are using their Lockfiles in the cached version):

| Tool          | Uncached Time   | Cached Time  |
| ------------- |:---------------:| ------------:|
| Yarn 1.2.1    | 437.24s         | 108.11s      |
| NPM  3.10.10  | 279.57s         | 204.94s      |
| NPM  5.1.1    | 107.62s         | 58.09        |

That's a pretty incredible improvement compared to the old version of NPM and Yarn. Other people are not seeing such a noticeable speedup in [their tests](http://blog.scottlogic.com/2017/06/06/does-npm5-deprecate-yarn.html) but on our project on my machine there is a big change.

It also doesn't seem possible given that the uncached version of NPM 5.1.1 is running faster than the cached version of Yarn. I've run those examples multiple times though and in case I didn't something terribly wrong, the safe takeaway is that NPM 5.1.1 has significant performance improvements that now make it comparable to Yarn.

# Where Yarn is Today

Given that we were using Yarn 0.27.5, there are some welcome features in Yarn 1.2.1. Facebook discusses some of them (here)[https://code.facebook.com/posts/274518539716230/announcing-yarn-1-0/]
and the ones that matter the most to me are the new automatic merge conflict resolution in the yarn.lock and the resolutions feature.

We use npm packages to manage many of our internal cross-team dependencies and since changes happen pretty rapidly, we often need to resolve merge conflicts
in the yarn.lock between team members. Doing it manually has led us to problems before when we've failed to resolve the changes properly and sometimes it can just be a long process.

Yarn now includes an auto-merge feature that allows you to just run `yarn install` when a merge conflict is generated and have it resolve the conflict and if successful save it to disk [7] https://code.facebook.com/posts/274518539716230/announcing-yarn-1-0/.

Another useful change is the new resolutions feature that allows you to specify patterns in the top level `package.json` and have any matching packages in nested package dependencies use that specified version, regardless of the version they have specified. This feature is useful when you need to enforce that sub-dependencies upgrade to fix a security vulnerability, or in our case use React < 0.16.0 even if they had specified >= 0.14.0 (I'll comeback to that problem in a future post).

# What Does the Future Look Like?

I think that given the closing performance gap and native lockfile support, NPM makes a compelling argument for our future package management. I am going to give both Yarn 1.2.1 and NPM 5.1.1 a try and discuss it with the team. I'm excited to see the direction both package managers go and am interested by Yarn's statement that we could see closer involvement between the two tools going forwards.
