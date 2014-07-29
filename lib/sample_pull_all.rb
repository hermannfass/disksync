#!/usr/bin/env ruby
$:.push('.')
require 'disksync'
ds = Disksync::DiskSynchronizer.new
ds.add_ssh_option( {
    host: 'rsync.hidrive.strato.com',
    user: 'hermannfass'
} )
ds.local_base_path = '_local_working_copy'
ds.remote_base_path = File.join('users', 'hermannfass')
ds.data_subdirs = ['MeineDokumente']

ds.synchronize_all(:pull)
