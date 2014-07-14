require "disksync/version"

# Class to manage information about the computer on which the code is
# executed, e.g. retrieving the path to a recently mounted USB volume or the
# type of Operating System.
class ComputerSystem

    # Where MacOS systems usually automount external volumes when connected.
    DefaultMacUsbMountPointParent = '/Volumes'

    # Where Cygwin systems usually automount external volumes when connected.
    DefaultCygwinUsbMountPointParent = '/cygdrive'

    # To do: Where Cygwin systems usually automount external volumes when connected.
    # DefaultLinuxUsbMountPoint = ''

    # Symbol naming the Operating System (family) of this system (:mac,
    # :linux, :cygwin).
    attr_reader :os

    # Where to find the executable Rsync programme.
    attr_reader :rsync_path

    def initialize()
        @os = case RUBY_PLATFORM
            when /darwin/i then :mac
            when /linux/i then :linux
            when /cygwin/i then :cygwin
        end
        @usb_parent_dir = case @os
            when :mac then DefaultMacUsbMountPointParent 
            when :cygwin then DefaultCygwinUsbMountPoint
            else 'undefined'
        end
        @rsync_path = `which rsync`.strip
    end

    # Escape paths as Rsync input on the specific OS
    def rsync_path_escape( path )
        if (@os == :mac)
            '"' + path + '"'
        else
            # Adapt to other OSs if necessary
            '"' + path + '"'
        end
    end

    # Escape paths for directory handling (e.g. Dir::mkdir)
    def ruby_path_escape( path )
        if (@os == :mac)
            '"' + path + '"'
        else
            # Adapt to other OSs if necessary
            '"' + path + '"'
        end
    end

    # Returns the path of the most recently mounted volume. The logic is that
    # when an external USB volume is connected for data synchronization, this
    # can most often be identified as the most recent mount point in the
    # system specific directory of mount points.
    def last_automounted_usb_volume()
        if (@os == :mac)
            File.join(
                DefaultMacUsbMountPointParent,
                Dir.entries(DefaultMacUsbMountPointParent).reject{ |f|
                    f.match(/\.\.?/)
                }.sort{ |a,b|
                    File.ctime( File.join(@usb_parent_dir, a) ) <=>
                    File.ctime( File.join(@usb_parent_dir, b) )
                }[-1]
            ) 
        elsif (@os == :cygwin)
            File.join(
                DefaultCygwinUsbMountPointParentPath,
                Dir.entries(DefaultCygwinUsbMountPointParent).reject{ |f|
                    f.match(/\.\.?/)
                }.sort{ |a,b|
                    File.ctime( File.join(@usb_parent_dir, a) ) <=>
                    File.ctime( File.join(@usb_parent_dir, b) )
                }[-1]
            ) 
        elsif (@os == :linux)
            # To do: Whatever will work for Linux goes here 
        else
            nil
        end
    end

end


# Can synchronize data between the user's directories (herein called 'local')
# and another disk, herein called 'remote' system. 
# Efficient use of this class works as follows:
# 1. Instantiate it.
# 2. Set @local_base_path (or leave default, DefaultLocalBasePath).
# 3. Set @data_subdirs to an Array of subdirectory names (for non-BLOB data).
# 4. Set @blob_subdirs to an Array of subdirectory names (for BLOBs).
# 5. Call the synchronize_all() method.
# 
# Alternatively:
# For individual directories you might as well call directly
# synchronize_subdir_list(), passing the names of the subdirectories to be
# synchronized in an Array. In that case, before calling
# synchronize_subdir_list(), set @effective_rsync_options appropriately.
class DiskSynchronizer

    DefaultLocalBasePath  = File.join( ENV['HOME'], '_local_working_copy' )
    DefaultDataSubdirs = [ 'MeineDokumente', '_security' ]
    DefaultBlobSubdirs = [ 'BLOBs' ]
    DefaultRsyncOptions = [ '-rtv', '--modify-window=2' ]
    DefaultDataRsyncOptions = [ '--delete' ]
    DefaultBlobRsyncOptions = [ '--size-only' ]

    # Base path under which the data (and BLOB) directories are located on the
    # local system.
    attr_accessor :local_base_path

    # Base path under which the data (and BLOB) directories are located on the
    # remote system (or USB volume).
    attr_accessor :remote_base_path

    # Array of subdirectory names in which the data to be synchronized with
    # the synchronize_all() method is located.
    attr_accessor :data_subdirs

    # Array of subdirectory names in which the BlOB data to be synchronized
    # with the synchronize_all() method is located.
    attr_accessor :blob_subdirs

    attr_accessor :effective_rsync_options

    # Rsync options for the synchronization of data (i.e. not BLOBs).
    # It should be possible to add appropriate optinos (-e) for Rsync-over-SSH.
    # This attribute is an Array of Strings that get joined with a space
    # character when included in Rsync calls.
    attr_accessor :data_rsync_options

    # Rsync options for the synchronization of BLOBs.
    # It should be possible to add appropriate optinos (-e) for Rsync-over-SSH.
    # This attribute is an Array of Strings that get joined with a space
    # character when included in Rsync calls.
    attr_accessor :blob_rsync_options

    # Direction of synchronization. Can be :push (from local to remote) or
    # :pull (vice versa). 
    attr_accessor :direction

    # This computer system (OS, path conventions etc.)
    attr_reader :this_system

    def initialize()
        @data_rsync_options = DefaultRsyncOptions + DefaultDataRsyncOptions
        @blob_rsync_options = DefaultRsyncOptions + DefaultBlobRsyncOptions
        @effective_rsync_options = @data_rsync_options
        @local_base_path  = DefaultLocalBasePath
        @this_system = ComputerSystem.new
        @remote_base_path = @this_system.last_automounted_usb_volume()
        @data_subdirs = DefaultDataSubdirs
        @blob_subdirs = DefaultBlobSubdirs
        @direction = :push
    end

    # Synchronize all subdirectories contained in @data_subdirs and
    # @blob_subdirs, applying the appropriate rsync options for data and BLOBs
    # accordingly.
    def synchronize_all( direction = @direction )
        puts "Preparing to #{direction} all data and BLOB directories."
        @effective_rsync_options = @data_rsync_options
        self.synchronize_subdir_list( @data_subdirs, direction )
        @effective_rsync_options = @blob_rsync_options
        self.synchronize_subdir_list( @blob_subdirs, direction )
    end

    # Synchronize a list of subdirectories from @local_base_path to
    # @remote_base_path (when direction is :push) or in the opposite
    # direction (when direction is :pull).
    # Subdirectories (subdirs) that do not exist in the @local_base_path or in
    # the @remote_base_path get skipped. Thus, when pushing to a remote disk
    # make sure the top level directories are existing.
    def synchronize_subdir_list( subdirs, direction = @direction )
        puts "\nTrying to #{direction} the following subdirectories:"
        subdirs.each { |d| puts "  - #{d}" }
        subdirs.each do |d|
            puts "\n#{d}:"
            local_path = File.join( @local_base_path, d )
            unless File.directory?(local_path)
                puts "#{local_path} not on local disk. Skipped!"
                next
            end
            puts "#{local_path} exists on local disk."
            remote_path = File.join( @remote_base_path, d ) 
            unless File.directory?(remote_path)
                puts "#{remote_path} does not exist on remote disk. Skipped!"
                next
                # To do:
                # Creating the directory on a USB device fails with an
                # error message about permissions that seems
                # inappropriate. Find out and activate the the
                # following code again when solved.
                #
                # print "Do you want to create it (y/n)? "
                # if ( gets.strip.match(/y/i) )
                #     puts "Creating directory #{remote_path} (" +
                #         @this_system.ruby_path_escape( remote_path ) + ")"
                #     Dir.mkdir( @this_system.ruby_path_escape(remote_path) )
                # else
                #     next
                # end
            end
            puts "#{remote_path} exists on remote disk."
            # Either local and remote path exists or we have have jumped to
            # the next sub directory with 'next' statement.
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
            @this_system.rsync_path,
            @effective_rsync_options.join(' '),
            @this_system.rsync_path_escape( File.join(source_path, '') ),
            @this_system.rsync_path_escape(target_path)
        ].join(' ')       
        puts "Calling Rsync (#{direction}ing)"
        puts rsync_call
        system( rsync_call )
        puts "Done."
    end
    
end






