---
layout: post
title: Manage Project Setup with Tmux
image: '/images/tech/tmux.png'
image-text-color: 'light'
category: Tech,
tags: [project, tmux, terminal]
---

I recently joined a team working developing a JavaScript web app and like the beginning of all projects, I had to ramp up on how to run the application locally.

<!--halt-->

# Terminal Management

This natural step in the development process can be eased by services like Vagrant that can install all the required dependencies and create a standard environment that will minimize the classic *it works on my machine* problems that you run into with setting up an environment.

We were using vagrant, but there were still a number of things to run in the command line before I could get going and I'm sure many web developers can relate. I had to do `npm run dev` locally for fast hot reloading of assets, ssh into vagrant to run the server also using npm, as well as start some required services on the vm, tail some log files and set up a db console for convenience.

I initially wrote down these steps which was fine, since I rarely restart my computer it isn't too much of a hassle to re-run everything and then tab between my different terminals.

# Using Tmux Effectively

I had used tmux for basic things in the past, mostly just to split screen my terminal and run both a server and git side-by-side. If you have not used it before, it has a pretty straightforward terminal multiplexing strategy:

Each instance of tmux is called a session. Sessions have windows that are essentially tabs like you have with any terminal and windows can be broken into sections called panes. You can have multiple sessions running at once and attach or detach from them to access their windows with your desired layout and sizes of panes. Within a tmux session you can use a defined prefix followed by a key combination to run different commands. For example, the default on my linux machine is `ctrl-b [command]`.

You can do a lot with tmux but I typically only use a small set of core commands to manage my sessions:

# CLI Commands:

* `tmux`: Start tmux, bare minimum to know
* `tmux ls`: List all running tmux sessions
* `tmux a -t [name || number]`: Attach to a running session by its number or given name
* `tmux kill-session -t [name || number]`: Stop the session by number or name

# Prefixed commands:

* `?`: List all commands and their keybindings
* `:`: Open the tmux command line to enter any command
* `"`: Split current pane vertically
* `%`: Split current pane horizontally
* `z`: Expand the current pane to the full size of the window, hiding all other panes
* `[`: Enter scroll mode scrolling in the current pane, by default you cannot scroll
* `x`: Kill the current pane
* `c`: Create another window
* `w`: Open menu to switch windows
* `[number]`: Switch to the window with the provided number
* `s`: Open menu to switch sessions
* `d`: Detach from the current session

# Managing a Project

These core features make it pretty easy to get the layout of logs, consoles, and servers that I need to setup for my application, but I still have to set all of this up every time I reboot.

I wanted something that would do all of that automatically for me and I heard about a powerful tmux manager and ruby gem aptly named [Tmuxinator](https://github.com/tmuxinator/tmuxinator).

Tmuxinator lets you define a YAML config file that pre-configures your sessions and panes so that you can set up the layout and automatic commands that should be run in your windows and panes.

My multi-step setup became a relatively simple tmuxinator config like this:

{% highlight yaml %}
name: generic-project-name
root: /Projects/generic-project
windows:
  - main:
    layout: tiled
    panes:
      # Run application server
      - vagrant_server:
        - cd <%= @settings['project_path'] %>
        - ssh -F ./custom_config default
        - cd <%= @settings['mount_path'] %>
        - NODE_ENV=development npm run start
      # Open DB console
      - vagrant_db:
        - cd <%= @settings['project_path'] %>
        - ssh -F ./custom_config default
        - cd <%= @settings['mount_path'] %>
        - make dbconsole
      # Run Hot Reloading
      - local_server:
        - cd <%= @settings['project_path'] %>
        - npm run start-dev
      - local_terminal:
        - git status
      - system:
        - htop
{% endhighlight %}

You can create any number of tmuxinator configs with the `tmuxinator new [name]` command that creates a
config file in the `~/.tmuxinator/[name].yml`.

With this particular config I can then run `tmuxinator start generic-project-name` and start a new tmux
session named **generic-project-name** with one window and 5 different panes distributed
in a tile layout of three panes per row. You can choose different types of pre-configured
layouts or import your own with the exact sizing and placement of panes that you prefer.

At this point I can put away my notes and not have to worry about doing anymore manual setup.
On a big monitor I can now manage my vagrant database console, servers, git, and system processes via htop,
a human-readable `top` command, all at a glance.

One thing to note is that you are able to issue commands using tmuxinator even within a ssh connection.
This works because Tmuxinator passes input directly to send keys so that the
commands are sent to the shell as if you had typed them in yourself.

Also, I am using a custom ssh command rather than the normal `vagrant ssh`. At least
at the time I first tried this, starting multiple vagrant shells in parallel
was causing race conditions that could cause one or multiple connections to fail, so I switched to
a plain ssh command.

Another important feature is that the file supports [ERB](https://en.wikipedia.org/wiki/ERuby#erb)
for evaluating dynamic values that can be environment variables, or a key value pair argument like
`tmuxinator new [name] key=value` to make values available in a `@settings` Ruby Hash.

This is a great feature for sharing configurations between developers, and that was the next step
for making our project's terminal management really simple.

# Sharing Configurations

This configuration file is awesome for getting developers going on a project. In a docker or vagrant world
setting up your system could theoretically be as simple as `vagrant up` followed by
`tmuxinator start [name]`.

The comments in the config can also describe what each step is doing, which can make what often feel like
magical commands when you're first getting used to a project more understandable. If you are forgetful like me,
you could even modify the config to `echo` a description of what each pane will be doing as its first command
until you get your bearings.

Our developers have many projects used by different combinations of teams so
for sharing the configurations we could place a `[project name].yml` file in each
of our repositories that developers could get for free when they clone it.

They could then symlink the file to the `~/.tmuxinator/[name].yml` and start the session.
For some teams this could involve starting multiple tmuxinator sessions for the
different projects that they interact with daily.

This was pretty convenient, and to make it controversially simpler I made a second
gem called [nerdinator](https://github.com/danReynolds/nerdinator).

When you download the repo containing the config file, you can run `nerdinator add [namespace]`
to automatically symlink the config to the tmuxinator directory and add it to the provided
namespace.

Once you have added some configurations, you can then start combinations of projects:

{% highlight bash %}
cd ~/service1
nerdinator add webservices/service1
cd ~/service2
nerdinator add webservices/service2
cd ~/api
nerdinator add webapis/api
nerdinator start webservices
tmux a -t service1 # Attach to service1
{% endhighlight %}

You can then perform actions like:

{% highlight bash %}
nerdinator list
webservices:
  service1
  service2
webapis:
  api
{% endhighlight %}

{% highlight bash %}
nerdinator start webservices
// start service1
// start service2
{% endhighlight %}

{% highlight bash %}
nerdinator start
// start service1
// start service2
// start api
{% endhighlight %}

There are a number of additional features I want to add to nerdinator, but for now I'm happy with how it lets me easily
start all of my tmuxinator sessions for our projects.

Some features I want to add in the near future:

1. Better error handling for invalid namespaces and other commands
2. Flags for auto attaching to the session
3. Command for initializing the current directory with an unconfigured tmuxinator.yml

At this point I have come a long way from writing down a bunch of commands on a notepad
and I'm really pleased with the setup I've made for managing all of my terminals.

For anyone who has similar requirements either at work or on their personal projects,
I'd highly recommend trying out tmux and tmuxinator.
