# require "disksync/version"

# module Disksync
  # Your code goes here...
# end

class DiskSynchronizer

    DefaultBasePath = '~/_local_working_copy'
    DefaultDataSubdirs = [ 'MeineDokumente', '_security' ]
    DefaultBlobSubdirs = [ 'BLOBs' ]
    DefaultRsyncOptions = [ '-rtv', '--modify-window=2' ]
    DefaultDataRsyncOptions = [ '--delete' ]
    DefaultBlobRsyncOptions = [ '--size-only' ]

    attr_accessor :data_subdirs
    attr_accessor :blob_subdirs
    attr_accessor :rsync_options


    def initialize()
        rsync_path = `which rsync`
    end

    def synchronize_all()
        if (@data_subdirs.empty?)
            @data_subdirs = DefaultDataSubdirs.collect {|d| File.directory?(d)
}
        @data_subdirs = DefaultDataSubdirs.collect if (@data_subdirs.empty?)
        @blob_subdirs = DefaultDataSubdirs if (@blob_subdirs.empty?)
        @data_subdirs.each |dir|
            synchronize
        

    end

    def available_default_data_subdirs()
        @data_subdirs.collect { |d| File.directory?(d) }
        
        

end








