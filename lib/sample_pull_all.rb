#!/usr/bin/env ruby
require 'disksync'
ds = DiskSynchronizer.new
ds.synchronize_all(:pull)
