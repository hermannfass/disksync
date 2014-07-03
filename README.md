# Disksync

Library for creating data synchronization tools. This will also include one
specific tool, 'disk', with that a user can keep data on different disks in
sync.

The original motivation was to be able to update USB disks and to write back
changes on other systems by means of a USB disk. This includes considerations
like available disk space: You do not want to push your video collection to a
4 GB USB stick.

Rsync via SSH will be supported as well.

At the time of writing this project has just started, so that the code is not
supposed to work or to be used.

## Installation

Add this line to your application's Gemfile:

    gem 'disksync'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install disksync

## Usage

require 'disksync'

sync = DiskSynchronizer.new( '~/mydata', '/Volumes/myusb/mydata' )
sync.pull


## Contributing

1. Fork it ( https://github.com/[my-github-username]/disksync/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
