Jenkins 8000 – Automated Jenkins Installation with Puppet
Overview

This project provides a fully automated, hands-off installation of Jenkins using plain Puppet (no Forge modules), designed to work across common Linux distributions.

The goal is simple:

Start with a fresh Linux server

Run one command

End up with Jenkins running and reachable on port 8000

No manual steps, no clicking around, no post-install tweaking required.

This was intentionally built to be:

Idempotent (safe to run multiple times)

Cross-platform (Debian/Ubuntu and RHEL-family)

Readable and explainable, not “magic”

What this project does

When run, the project will:

Install Puppet (if it isn’t already installed)

Configure the official Jenkins package repository

Install Java (OpenJDK 17) and Jenkins

Force Jenkins to listen on port 8000

Explicitly enforced via a systemd override on Ubuntu to avoid distro quirks

Start and enable the Jenkins service

Optionally display the Jenkins initial unlock token in a clean, readable message

Everything is automated. The user running it does not need to answer prompts or edit files.

Supported operating systems

Ubuntu 20.04 / 22.04

RHEL / Rocky Linux / AlmaLinux 8 & 9

The manifest detects the OS family at runtime and applies the correct logic automatically.

Project files
bootstrap.sh

This is the entry point.

Installs Puppet if required

Runs the Puppet manifest

Verifies Jenkins is listening on port 8000

This is the only command the user needs to run.

jenkins8000.pp

The Puppet manifest that does the real work.

It:

Configures repositories securely

Installs required packages

Handles OS-specific differences cleanly

Forces Jenkins onto the chosen port

Optionally prints the Jenkins unlock token

No Puppet Forge modules are used.

Configuration

At the top of jenkins8000.pp there are a few clearly marked variables:

$jenkins_port = 8000
$show_jenkins_unlock = false


$jenkins_port
Jenkins will bind to this port.
No checks are performed for port availability (not required by the brief).

$show_jenkins_unlock
When set to true, the initial Jenkins unlock token is printed in a tidy message.
This is intentional and useful for first-time setup, and can be disabled easily.

How to run

On a fresh server:

chmod +x bootstrap.sh
sudo ./bootstrap.sh


That’s it.

Once complete, Jenkins will be available at:

http://<host>:8000/login

Notes on security and design choices

Repository signing and verification are enforced

Jenkins is configured explicitly rather than relying on defaults

The unlock token output is opt-in and clearly documented

The solution avoids unnecessary complexity (no Hiera, no roles/profiles)

All changes are idempotent and safe to re-apply

Why this approach

This project is intentionally practical rather than clever.

The aim is to demonstrate:

Clear automation logic

Awareness of OS differences

Safe defaults

Readable, maintainable Puppet code

A “one command and done” user experience

If this were extended further, it could easily be turned into a reusable Puppet module, but for the scope of this task, keeping everything explicit and visible was a deliberate choice.
