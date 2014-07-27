$:.push('.') # For local non-Gem tests only. Remove.
require 'disksync/version'
require 'disksync/computersystem'
require 'pp'

# Synchronization of files to external hard disks or to remote systems.
#
# Minimal example: The following will synchronize all subdirectories of your
# home directory onto the corresponding file on a USB device mounted under
# /Volumes/MYDISK:
#
#     ds = Disksync::DiskSynchronizer.new()
#     ds.remote_path = '/Volumes/MYDISK'
#     ds.synchronize_all
#
# Example using SSH on a remote system nas.home.test where your username is
# 'boss' and you connect with an RSA private key 'me_rsa' that is located in
# your .ssh directory::
#
#    ds = Disksync::DiskSynchronizer.new()
#    ds.local_base_path = 'Documents'
#    ds.data_subdirs = ['Lyrics', 'Stories']
#    ds.blob_subdirs = ['Music']
#    ds.add_ssh_option( {key: 'me_rsa', host: 'nas.home.test', uid: 'boss'} )
#    ds.synchronize_all
#
module Disksync

    DefaultDataDir     = '_local_working_copy'
    DefaultBlobSubdirs = [ 'BLOBs' ]
    DefaultDataRsyncOptions = {
                                standard:      '-rtv',
                                timetolerance: '--modify-window=2',
                                # deletions:     '--delete'
                              }
    DefaultBlobRsyncOptions = {
                                standard:      '-rtv',
                                timetolerance: '--modify-window=2',
                                timecheck:     '--size-only'
                              }


    # Can synchronize data between the user's directories (herein called 'local')
    # and another disk, herein called 'remote' system. 
    # Efficient use of this class works as follows:
    # 1. Instantiate it.
    # 2. Set @local_base_path (default is your home directory)
    # 3. Put some directory names under this into @data_subdirs. The default
    #    for this will be all directories in your home which might be by far more
    #    than you are willing to synchronize.
    # 4. Directories with large binary files might go into @blob_subdirs
    #    instead. That will avoid deletions and consider a file  unchanged if
    #    it still has the same file size.
    # 5. Call the synchronize_all() method.
    # 
    # Alternatively:
    # For individual directories you might as well call directly
    # synchronize_subdir_list(), passing the names of the subdirectories to be
    # synchronized in an Array. In that case, before calling
    # synchronize_subdir_list(), set @effective_rsync_options appropriately.
    class DiskSynchronizer

        # Base path under which the data (and BLOB) directories are located on the
        # local system. Defaults to directory DefaultDataDir (constant value)
        # in the home directory of the user.
        # Writer (setter) method implemented separately.
        attr_reader :local_base_path

        # Base path under which the data (and BLOB) directories are located on the
        # remote system (or USB volume). Defaults to directory DefaultDataDir
        # (constant value) in the home directory on the remote system (or root
        # of the USB volume).
        attr_accessor :remote_base_path

        # Remote host for synchronization over SSH. This is set when the SSH
        # option is defined and removed when the SSH option gets disabled.
        attr_accessor :remote_host

        # Array of subdirectory names in which the data to be synchronized with
        # the synchronize_all() method is located. Defaults to the elements of
        # the constant Array DefaultDataSubdirs.
        attr_accessor :data_subdirs

        # Array of subdirectory names in which the BlOB data to be
        # synchronized with the synchronize_all() method is located. Defaults
        # to the elements of the constant Array DefaultBlobSubdirs.
        attr_accessor :blob_subdirs

        # Hash with Rsync options for the synchronization of BLOB data.
        # Having this set permanently available should allow easily to switch
        # between BLOB and normal data transfer - by assigning this value to the
        # @effective_rsync_options before the call of the synchronize() method
        # or other methods that invoke Rsync system calls.
        attr_accessor :effective_rsync_options

        # Rsync options for the synchronization of data (i.e. not BLOBs).
        # Having this set permanently available should allow easily to switch
        # between data and BLOB data transfer - by assigning this value to the
        # @effective_rsync_options before the call of the synchronize() method
        # or other methods that invoke Rsync system calls.
        attr_accessor :data_rsync_options

        # Rsync options for the synchronization of BLOBs.
        # It should be possible to add appropriate optinos (-e) for Rsync-over-SSH.
        # This attribute is an Array of Strings that get joined with a space
        # character when included in Rsync calls.
        attr_accessor :blob_rsync_options

        # Direction of synchronization. Can be :push (default, meaning from
        # local to remote) or :pull (vice versa). 
        attr_accessor :direction

        # This computer system (OS, path conventions etc.) as a ComputerSystem
        # instance.
        attr_reader :myhost

        # Constructor. Sets default values for most settings.
        def initialize()
            @myhost = ComputerSystem.new
            @local_base_path = @myhost.user_home_dir # default
            @data_rsync_options = DefaultDataRsyncOptions
            @blob_rsync_options = DefaultBlobRsyncOptions
            @effective_rsync_options = @data_rsync_options
        end

        # Set the @local_base_path attribute.
        # The path may an be absolute path (i.e. start with '/') or a path
        # relative to the user's home directory.
        def local_base_path=(path)
            if ( path.start_with?('/') )
                @local_base_path = path
            else
                @local_base_path = File.join(@myhost.user_home_dir, path)
            end
        end

        def ssh?()
            @effective_rsync_options.has_key?(:ssh)
        end

        # Configure for transferring the data to/from a remote host via SSH.
        # This manipulates @data_rsync_options, @blob_rsync_options, but also the
        # @effective_rsync_options.
        # Argument can be a Hash with the following keys (examples):
        # ssh_path (system's path to ssh executable, e.g. '/usr/bin/ssh',
        # detected automatically), user_id (ID of the user executing
        # the SSH call, detected automatically), key_path (path to the private
        # RSA key, defaults to $HOME/.ssh/id_rsa, host (not needed for the SSH
        # option but to set the @remote_host to a FQDN of the remote host
        # involved in the synchronization.
        def add_ssh_option( ssh_settings = {} )
            ssh_path = ssh_settings[:ssh] || @myhost.ssh_path
            user_id = ssh_settings[:uid]  || @myhost.user_id
            key_path =
                if ( File.exist?(ssh_settings[:key]) )
                    ssh_settings[:key]
                elsif ( File.exist?( p = File.join(
                                           @myhost.default_private_key_dir,
                                           ssh_settings[:key])) )
                       p
                elsif ( File.exist?(@myhost.default_private_key_path) )
                    @myhost.default_private_key_path
                else
                    raise "Cannot find private key for SSH"
                end
            ssh_option = "-e '#{ssh_path} -i #{key_path} -l #{user_id}'"
            @data_rsync_options[:ssh]      = ssh_option
            @blob_rsync_options[:ssh]      = ssh_option
            @effective_rsync_options[:ssh] = ssh_option
            @remote_host = ssh_settings[:host]
            @ssh = true
            @direction = :push
        end

        # Take out the SSH aspect of the data synchronization. This will
        # modify theremote_base_path (when direction is :push) or in the opposite
        # direction (when direction is :pull).
        # The first argument is an Array of subdirectories, i.e. directories
        # below the base path, that should get synchronized. The second
        # argument is the direction which can be :push (default, i.e. move
        # data from the local system ro remote system or USB disk) or :pull
        # (vice versa).
        # Subdirectories (subdirs) that do not exist in the @local_base_path or in
        # the @remote_base_path get skipped. Thus, when pushing to a remote disk
        # make sure the top level directories are existing.
        def synchronize_subdir_list( subdirs, direction = @direction )
            puts "\nTrying to #{direction.to_s} the following subdirectories:"
            subdirs.each { |d| puts "  - #{d}" }
            subdirs.each do |d|
                puts "\n#{d}:"
                local_path = File.join( @local_base_path, d )
                unless File.directory?(local_path)
                    puts "#{local_path} not on local disk. Skipped!"
                    next
                end
                puts "#{local_path} exists on local disk."
                if ( @remote_base_path.nil? )
                    if ( self.ssh? )
                        @remote_base_path = ''
                    else
                        @myhost.guess_usb_volume
                    end
                end
                if ( self.ssh? )
                    remote_path = "#{@remote_host}:" +
                          ( (@remote_base_path.empty?) ?
                            (d) :
                            (File.join(@remote_base_path, d)) )
                else
                    remote_path = File.join( @remote_base_path, d )
                end
                self.synchronize( local_path, remote_path, direction )
            end
        end

        # Synchronize a local directory to a remote directory (direction :push) or
        # vice versa (direction :pull). The path names are full path names. You
        # can use this method, but it is recommended to set the base directories
        # and the subdirectory lists (@data_subdirs, @blob_subdirs)
        # correctly and then use the synchronize_all().
        def synchronize( local_path, remote_path, direction = @direction )
            # Construct Rsync call and go
            if (direction == :push) 
                source_path = local_path
                target_path = remote_path
            else
                source_path = remote_path
                target_path = local_path
            end
            rsync_call = [
                @myhost.rsync_path,
                @effective_rsync_options.values.join(' '),
                @myhost.rsync_path_escape( File.join(source_path, '') ),
                @myhost.rsync_path_escape(target_path)
            ].join(' ')       
            puts "Calling Rsync (#{direction.to_s}ing)"
            puts rsync_call
            result = system( rsync_call )
            # To do: Evaluate return value including error handling
            puts "Done."
        end

    end

end

