---
layout: post
title: Locking Down your Dependencies
image: '/images/tech/dependencies.png'
category: Tech
tags: [project, yarn, dependencies, npm]
---

It is important to ensure that both your development and production environments
are using the dependencies that you expect. As I've found before, Yarn and npm
behave a little differently.

<!--halt-->

# The Need for Lockfiles

Dependency management is an important factor in developing and deploying reproducible
builds. In the JavaScript world developers have had the option of using npm shrinkwrap
for years and in the past year both Yarn and npm have come up with their own automatic
lockfile solutions with the `yarn.lock` and `package-lock.json` files respectively.

Theses lockfiles make sure that if you share your code with team members or deploy it
to production, the packages your project depends on won't pull in breaking versions that
authors have published since the time you first worked on and tested the code.

While both package managers use lockfiles to determine your versions, they do not behave exactly the same.

# The Yarn.lock

If you run `yarn` in a fresh repo with no lockfile and a `package.json` it will install your dependencies and
create a `yarn.lock`.

The lockfile can be updated when you run `yarn add/upgrade/remove` as well as certains cases of `yarn install`. There has been debate around when the lockfile is actually changed on an install and I had initially thought that it could suck down newer versions of packages matching the semantic version range specified in the `package.json`, an issue brought up [here]*https://github.com/yarnpkg/yarn/issues/570#issuecomment-257136286). If this was the case then it defeats the purpose of a lockfile, as build servers and other developers could get different versions just by cloning a repo and running `yarn`.

After investigating further it became clear when Yarn actually updates the lockfile.

Yarn member thejameskyle recommends that you consider Yarn dependency management to behave like a memoize function:

>
  Imagine a memoize function where the input is a package.json and the output is the yarn.lock.

  1. The first time you pass a package.json it creates a yarn.lock and caches the result.
  2. The next time you run that same package.json the result will be exactly the same because it is cached.
  3. When you change the package.json you've invalidated the cache and now the yarn.lock will be recalculated.

  It's more complex than I've made it out to be (each package version gets effectively "memoized" individually, changing the version of one package doesn't invalidate the rest), but hopefully now everyone gets the point.

Each package is effectively going to use the version specified in the lockfile unless it or its parent dependencies was altered in the `package.json`, in which case it is going to get the **latest compatible version** even if a different compatible version is already present in the lockfile as described in testing by CrabDude [here](https://github.com/yarnpkg/yarn/issues/570#issuecomment-274638907).

This behavior is much closer to npm than I had originally described, but still slightly different.

# The package-lock.json

The `package-lock.json` was only released in npm 5 earlier this year and there has been **a lot** of [back and forth](https://github.com/npm/npm/issues/17979) by developers on how its lockfile should work.

At the time of this post, an employee at npm described how it works in version `> 5.4` pretty well [here](https://github.com/npm/npm/issues/17979#issuecomment-332701215).

In her explanation she said the following:

>
1. If you have a package.json and you run npm i we generate a package-lock.json from it.
2. If you run npm i against that package.json and package-lock.json, the latter will never be updated, even if the package.json would be happy with newer versions.
3. If you manually edit your package.json to have different ranges and run npm i and those ranges aren't compatible with your package-lock.json then the latter will be updated with version that are compatible with your package.json. Further runs of npm i will be as with 2 above.

Whereas changing a package in the `package.json` will always grab the latest compatible version under Yarn and update the lockfile, npm will keep the current version in the lockfile if it is still within the compatible range.

# Takeaway

It wasn't always clear how Yarn and npm treat their dependency management and it took some digging to determine the actual behavior of each package manager.

Hopefully this has made lockfile management a little clearer using either Yarn or npm.
