---
layout: post
title: Revisiting Yarn and npm
image: '/images/tech/yarn.png'
category: Tech
tags: [project, yarn, javascript]
---

Yarn 1.0 has been out for a while now and in the process of upgrading from version 0.27.5 to 1.2.1 I've decided to
take another look at Yarn and what makes it different from npm.

<!--halt-->

# How We Use It

We Have been using Yarn for a while on our project, but overall I've found it to be pretty interchangable with npm besides the fact that by default
it uses a lockfile.

Overtime some of our teams have kept using npm, some use Yarn for its default lock file, and some use it without a lockfile. This has led
me to the conclusion that most people aren't too opinionated on the version manager we use either way and I wanted to take a brief look
into some of the different features and implementations of each option.

# The Case for Yarn

The benefits I initially heard about Yarn when it came out were that it is generally faster than npm and uses a lockfile to ensure that you end up getting deterministic dependencies.

In terms of speed, Yarn downloads dependencies in parallel and stores them in a global cache that makes repeat installs really fast. That's awesome and Yarn's install speed is one of the big
reasons for using it over npm.

npm also has its own cache, however, which stores all http request data that npm fetches {% cite npm-cache %} and that you can prioritize by setting the flag `prefer-offline`
in your npm config, usually located at `~/.npmrc` {% cite npm-config %}. With this flag, npm will favor using cached packages and only fetch it from the online repositories when there is a cache miss.

I wanted to test the install speeds of each package manager on our React Native project to get an idea about their performance differences with and without their respective caches. The quick tests I did yielded the following results:


| Tool          | Uncached Time   | Cached Time  |
| ------------- |:---------------:| ------------:|
| Yarn 1.2.1    | 437.24s         | 108.11s      |
| npm  3.10.10  | 279.57s         | 204.94s      |

Yarn definitely performs faster when cached, but is much slower on our large repo on an uncached install compared to npm. Since most of the time you should have the global cache, Yarn is the clear winner here.

In addition to speed, Yarn's other big selling point is that it by default provides a `yarn.lock` file, a dependency management system similar to cargo or bundler that installs a defined
version of dependencies and offer repeatable installations.

npm similarly has had support for version locked dependencies using the `npm shrinkwrap` command, which generates a `npm-shrinkwrap.json`
with dependency versions based on what is currently installed under the `node_modules` folder {% cite npm-shrinkwrap %}.

Yarn describes its locking mechanism as similar to shrinkwrap, with the added benefit that it is *fully automatic and that it’s not lossy and it creates reproducible results* {% cite yarn-lock %}.

I wasn't exactly sure what it meant by shrinkwrap being lossy and not reproducible and there is actually an issue recently opened on Yarn for this [exact question](https://github.com/yarnpkg/website/issues/509). The top answer from
Google can also be [read here](https://stackoverflow.com/questions/40057469/what-is-the-difference-between-yarn-lock-and-npm-shrinkwrap/40057535#40057535) and talks about how npm-shrinkwrap can lead to non-deterministic results.

This seems at odds with the purpose of shrinkwrap, which which it was introduced was described as follows {% cite npm-shrinkwrap %}:

> When "npm install" installs a package with a npm-shrinkwrap.json file in the package root, the shrinkwrap file (rather than package.json files) completely drives the installation of that package and all of its dependencies (recursively).

I believe that the difference is that shrinkwrap only locks down your dependency versions, but not actually the contents of the dependencies, allowing authors to force updates to their libraries or re-publish
them. The creators of npm shrinkwrap recommend that {% cite shrinkwrap-dependencies %}

> If you wish to lock down the specific bytes included in a package, for example to have 100% confidence in being able to reproduce a deployment or build, then you ought to check your dependencies into source control, or pursue some other mechanism that can verify contents rather than versions.

Yarn on the other hand makes it clear that it uses checksums to determine the integrity of every piece of code you download. You can run this yourself with the `yarn check --integrity` {% cite yarn-check %}.

Based on the speed and integrity differences between npm and Yarn it looks like it was definitely a valuable addition to the lives of JavaScript developers.

# Where npm is Today

As I looked to upgrade our version of Yarn I wanted to check the current state of npm to determine if Yarn still makes a compelling argument for first-class performance and stability through deterministic dependency management.

npm launched version [5.0](http://blog.npmjs.org/post/161081169345/v500) earlier this year and with it come some nice improvements. For one, npm now uses a standardized, deterministic lockfile implementation called a `package-lock.json` which will be automatically created when packages are installed unless an `npm-shrinkwrap.json` already exists and takes precedence if they both do. It also verifies packages against tarballs in the cache to ensure integrity.

It looks like npm heard the community's enthusiasm for Yarn's lockfiles loud and clear.

Both Yarn and npm 5 now support deterministic lockfiles, with some interesting differences that you can read about in full [here](https://yarnpkg.com/blog/2017/05/31/determinism/).

Yarn guarantees deterministic lockfiles only across the **same version** of Yarn. `yarn.lock` files are flat and do not have any information on the hoisting and position of top level dependencies. Yarn internally determines the positioning of packages to go in the node_modules, meaning that the result could vary with different Yarn versions. The primary benefit of this approach is that the yarn.lock file is easier to diff and resolve merge conflicts with than a nested JSON structure.

Alternatively, npm 5 uses a JSON lockfile that already has its dependencies hoisted in the exact position that they are structured in the node_modules folder, meaning that two developers on different versions can use the same lockfile and definitely produce the same directory structure.

This led Yarn to make the following statement:

> npm 5 has stronger guarantees across versions and has a stronger deterministic lockfile, but Yarn only has those guarantees when you’re on the same version in favor of a lighter lockfile that is better for review. It’s possible that there’s a lockfile solution that has the best of both worlds, but for now this is current state of the ecosystem and possible convergence could happen in the future.

That's pretty cool that they're open to combining the systems in the future.

npm 5 also had it's cache implementation rewritten and while they did not say much about its speed improvements, [this clip](https://twitter.com/maybekatz/status/865393382260056064) they linked to in the release has me excited about giving it a try.

The previous performance tests above were run against our current npm version of 3.10.10, but let's see if bumping that to 5.5.1 gives us a strong improvement.

Using the latest npm version gave the following results (both npm 5.5.1 and Yarn 1.2.1 are using their Lockfiles in the cached version):

| Tool          | Uncached Time   | Cached Time  |
| ------------- |:---------------:| ------------:|
| Yarn 1.2.1    | 437.24s         | 108.11s      |
| npm  3.10.10  | 279.57s         | 204.94s      |
| npm  5.5.1    | 107.62s         | 58.09s       |

That's a pretty big improvement compared to the old version of npm and even Yarn. Other people are not seeing such a noticeable speedup in [their tests](http://blog.scottlogic.com/2017/06/06/does-npm5-deprecate-yarn.html) but in our project and on my machine this is a big change.

I'd be a little cautious about these stats given that the uncached version of npm 5.5.1 is running faster than the cached version of Yarn. I've run those examples multiple times with similar results but in case I did something terribly wrong, I would conclude that the safe takeaway is that npm 5.5.1 has significant performance improvements that now make it comparable to Yarn.

# Where Yarn is Today

Upgrading from Yarn 0.27.5 to 1.2.1 would also come with some welcome changes. Facebook discusses some of them [here](https://code.facebook.com/posts/274518539716230/announcing-yarn-1-0/)
and the ones that we are looking forward to the most are the new automatic merge conflict resolution in the yarn.lock and the resolutions feature.

We use npm packages to manage many of our internal cross-team dependencies and since changes happen pretty rapidly, we often need to resolve merge conflicts
in the yarn.lock between team members. Doing it manually has led us to problems before when we've failed to resolve the changes properly and sometimes it can just be a long process.

Yarn now includes an auto-merge feature that allows you to just run `yarn install` when a merge conflict is generated and have it resolve the conflict and if successful save it to disk {% cite yarn-debut %}.

The other nice change I'm interested in is the new resolutions feature that allows you to specify patterns in the top level `package.json` and have any matching packages in nested package dependencies use that specified version, regardless of the version they have specified. This feature is useful when you need to enforce that sub-dependencies upgrade to fix a security vulnerability, or in our case use React < 0.16.0 even if they had specified >= 0.14.0 (I'll comeback to that problem in a future post).

# What Does the Future Look Like?

I think that given the closing performance gap and native lockfile support, npm makes a compelling argument for our future package management. I am going to give both Yarn 1.2.1 and npm 5.5.1 a try and discuss it with the team.

I'm excited to see the direction both package managers go and am interested by Yarn's statement that we could see closer involvement between the two tools going forwards.

---
## References
