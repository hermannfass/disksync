$:.push('.') # For local non-Gem tests only. Remove.
require 'disksync/version'

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

    DefaultBlobSubdirs = [ 'BLOBs' ]

    # Default options set for the transmission of normal (non-BLOB) data.
    DefaultDataRsyncOptions = {
                                standard:      '-rtv',
                                timetolerance: '--modify-window=2',
                                deletions:     '--delete'
                              }

    # Default options set for the transmission of BLOB directories: Files
    # comparison is limited to file size only. This avoids transmission of
    # files where only the timestamp has been modified (usually by accident
    # without changing the file content).
    DefaultBlobRsyncOptions = {
                                standard:      '-rtv',
                                timetolerance: '--modify-window=2',
                                timecheck:     '--size-only'
                              }

    # What standard private key files to search for if nothing is configured
    # or specified when setting the SSH option.
    DefaultKeyFilenames = %w(id_rsa id_dsa id_ecdsa)

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
        # local system. Defaults to the user's home directory.
        # Writer (setter) method implemented separately.
        attr_reader :local_base_path

        # Base path under which the data (and BLOB) directories are located on the
        # remote system (or USB volume). Defaults to the user's home
        # directory on the remote system or to the root path on the connected
        # USB volume.
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

        # Constructor. Sets default values for most settings.
        def initialize()
            @local_base_path = Dir.home
            @data_rsync_options = DefaultDataRsyncOptions
            @blob_rsync_options = DefaultBlobRsyncOptions
            @rsync_bin_path = `which rsync`.strip
            @effective_rsync_options = @data_rsync_options
        end

        # Set the @local_base_path attribute.
        # The path may an be absolute path (i.e. start with '/') or a path
        # relative to the user's home directory.
        def local_base_path=(path)
            if ( path.start_with?('/') )
                @local_base_path = path
            else
                @local_base_path = File.join(Dir.home, path)
            end
        end

        def ssh?()
            @effective_rsync_options.has_key?(:ssh)
        end

        # Configure for transferring the data to/from a remote host via SSH.
        # This manipulates @data_rsync_options, @blob_rsync_options, but also the
        # @effective_rsync_options.
        #
        # If the SSH connection is configured in the SSH config file
        # (something like ~/.ssh/config) it is assumed that the FQDN
        # (HostName), the remote user (User), and the private key file
        # (IdentityFile) are configured properly for this host.
        def add_ssh_option( ssh_settings = {} )
            ssh_config_path = File.join(Dir.home, '.ssh', 'config')
            ssh_bin_path = `which ssh`.strip
            # ssh_spec is an Array of elements what follow Rsync's -e option
            # in single quotes):
            ssh_spec = [ssh_bin_path]
            @remote_host = ssh_settings[:host] if ssh_settings.has_key?(:host)
            if (File.readlines(ssh_config_path).grep(/#{@remote_host}/).any?)
                # SSH is configured in .ssh/config file.
                # Leave FQDN, username, or key file to this config
            elsif ( File.exist?(ssh_settings[:key]) )
                # Full path to private key was specified.
                # Use this file.
                ssh_spec << "-i #{ssh_settings[:key]}"
            elsif ( File.exist?( p = File.join(Dir.home,
                                               '.ssh',
                                               ssh_settings[:key]) ) )
                ssh_spec << "-i #{p}"
            end
            # To do: We could check if the username is configured in
            # .ssh/config at all and use ENV['USERNAME'] if it is not.
            if ( ssh_settings[:uid] )
                ssh_spec << "-l #{ssh_settings[:uid]}"
            end
            ssh_option = %q(-e ') + ssh_spec.join(' ') + %q(')
            @data_rsync_options[:ssh]      = ssh_option
            @blob_rsync_options[:ssh]      = ssh_option
            @effective_rsync_options[:ssh] = ssh_option
            @ssh = true
        end

        # Synchronize all directories in @data_subdirs and @blob_subdirs.
        def synchronize_all( direction = @direction )
            if (@data_subdirs.nil? or @data_subdirs.empty?)
                puts  "No subirectories specified for synchronization."
                print "Synchronize all under #{@local_base_path} (y/n)?"
                go = gets.chomp
                if (go == 'y')
                    @data_subdirs = Dir.entries(@local_base_path).select{ |d|
                                        d.directory?
                                    }.reject{ |d| d.match(/^\.\.?$/) }
                else
                    puts "No subdirectory means nothing to do. Aborting."
                    exit
                end
            end
            @effective_rsync_options = @data_rsync_options
            synchronize_subdir_list( @data_subdirs, direction )
            if (@blob_subdirs)
                @effective_rsync_options = @blob_rsync_options
                synchronize_subdir_list( @blob_subdirs, direction )
            end
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
            if ( subdirs.nil? or subdirs.empty? )
                raise ArgumentError, "No subdirectories specified for synchronization."
            end
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
                @rsync_bin_path,
                @effective_rsync_options.values.join(' '),
                ('"' + File.join(source_path, '') + '"'),
                ('"' + target_path + '"')
            ].join(' ')       
            puts "Calling Rsync (#{direction.to_s}ing)"
            puts rsync_call
            result = system( rsync_call )
            # To do: Evaluate return value including error handling
            puts "Done."
        end

    end

end

