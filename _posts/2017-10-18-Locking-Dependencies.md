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

While both package managers use lockfiles to determine your versions, but there are caveats.

# The Yarn.lock

Yarn's lockfile implementation is the most liberal. If you run `yarn` in a fresh
repo with no lockfile and a `package.json` it will install your dependencies and
create a `yarn.lock`.

When you go to deploy your code, you would need to once again install the dependencies and run `yarn`.
You are not, however, guaranteed to get exactly the same dependencies, even though you have a lockfile.

The most important file for determining the dependencies you should get is the `package.json`. If
your `package.json` has a semantic version of a package for `^0.1.1` and the package is currently published with `^0.1.2`, Yarn will install `^0.1.2` and indicate both the semantic range and the specific package it installed in the `yarn.lock`.

The author can then release version `^0.2.0` and a subsequent yarn would pull down that version and change the lockfile. That means that the code you share between team members or production deploys will isn't guaranteed to be exactly what you had developed with. This *should* be fine given that authors should not introduce breaking changes in a minor version bump.

One way to ensure that you don't have any problems would be to only select specific versions of packages in your `package.json`.

Another solution would be to run `yarn install --frozen-lockfile` described in the [Yarn docs](https://yarnpkg.com/lang/en/docs/cli/install/). The frozen flag will not allow the the lockfile to change and instead the install command will **fail**.

It could be frustrating to see builds fail because of frozen lockfile issues, but if that is happening too often and you don't want it to then that is a good indicator that the `package.json` should either use exact versions or be tested with the latest published versions of packages that match the version ranges before being deployed.

# The package-lock.json

The `package-lock.json` was only released in npm 5 earlier this year and there has been **a lot** of [back and forth](https://github.com/npm/npm/issues/17979) by developers on how its lockfile should work.

At the time of this post, an employee at npm described how it works in version `> 5.4` pretty well [here](https://github.com/npm/npm/issues/17979#issuecomment-332701215).

In her explanation she said the following:

>
1. If you have a package.json and you run npm i we generate a package-lock.json from it.
2. If you run npm i against that package.json and package-lock.json, the latter will never be updated, even if the package.json would be happy with newer versions.
3. If you manually edit your package.json to have different ranges and run npm i and those ranges aren't compatible with your package-lock.json then the latter will be updated with version that are compatible with your package.json. Further runs of npm i will be as with 2 above.

So npm will not install a new version of a package and update the lockfile even if it is the latest package in a compatible semantic range. The lockfile can still be modified by running `npm update` or when you change the `package.json` to an incompatible version and run `npm install`.

This behavior means that you can depend on shared projects and deploys to have the same dependencies as those that are specified in the lockfile.

# Takeaway

I think that whether you prefer getting the latest non-breaking versions with a `yarn install` or prefer locking down environments to specific versions depends on the packages you're working with, your project and your personal preference.

Hopefully this has made accomplishing either scenario a little clearer using either Yarn or npm.
