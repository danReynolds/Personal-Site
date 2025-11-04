---
layout: post
title: Handling Chrome's DPI Scaling
image: '/images/tech/chrome.png'
category: Tech
tags: [project, windows, chrome]
---

After building my UI on Linux, I popped onto Windows and realized that in Chrome
the interface had become larger, as if I was zoomed in.

<!--halt-->

# DPI Scaling

In Chrome 54, Google Chrome began to automatically use the Window's system's DPI (dots per inch)
setting to adapt the ratio of physical pixels to css pixels in the browser.

Not realizing it, my Dell installation of Windows had set a system default of 125% zoom on the machine
for High DPI screens. Once Chrome started taking this into account, the interface I had built on Linux
was too large once it was zoomed in and created a broken experience.

If you want to see for yourself you can go to [Summoner Expert](https://summonerexpert.com) and try manually
bumping the zoom to 125% and see how the layout overlaps.

This problem isn't specific to my site, other sites like GitHub are also more zoomed in but the change doesn't
seem to affect many sites to the point they have hurt its functionality.

# High Level Fix

I tried setting my system zoom to 100% which fixed the issue, but it caused the system UI to be unmanagbly small;
I see why Dell had set it larger by default. Buttons and other UI elements were jarringly tiny and it was less
usable. Besides, I couldn't ask anyone who visited the site to make the same change.

The solution I settled on was to determine the device's pixel ratio and programmatically change the zoom level in
CSS.

There is a property in the browser on the window object called `devicePixelRatio`, which returns the ratio of physical
to css pixels for the device and is meant to be used to deal with high DPI screens like Retina displays or the HD
screen on my XPS. You can learn more about it [here](https://developer.mozilla.org/en-US/docs/Web/API/Window/devicePixelRatio)
but they best describe it as the ratio of how many actual pixels the browser uses to draw a single CSS pixel.

```javascript
document.querySelector('body').style.zoom = `${1 / window.devicePixelRatio * 100}%`;
```

I added the above line to my `index.js` file and now calculate the zoom the screen should be at
based on the device's pixel ratio. On my Windows device this was 125% so now 1 / 1.25 = 0.8 or 80% zoom, negating the effect
of Chrome's calculations.

# Check Multiple Devices

My biggest take away here was that I should always test in multiple and platforms when building a website. Many users of the site
I found this problem on will likely be using Chrome on Windows and developing on Linux had not exposed this issue.

I am surprised more sites don't run into this, I haven't generally seen any zoom levels being set or had broken experiences, it's
possible that I am missing something. If you have any experience with this problem or know a better way to handle high DPI screens
let me know!
