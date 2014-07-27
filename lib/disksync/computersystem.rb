module Disksync

    # Class to manage information about the computer on which the code is
    # executed, e.g. retrieving the path to a recently mounted USB volume or the
    # type of Operating System.
    class ComputerSystem

        # Symbol naming the Operating System (family) of this system (:mac,
        # :linux, :cygwin).
        attr_reader :os

        # UID of the user running the application
        attr_reader :user_id

        # Home directory of the user running the application
        attr_reader :user_home_dir

        # Where to find the executable Rsync programme.
        attr_reader :rsync_path

        # Where to find the executable SSH programme (optional).
        attr_reader :ssh_path

        # The default directory where private key files are located.
        # Can be absolute or relative to the user's home directory.
        attr_reader :default_private_key_dir

        # The default private key file on this system.
        attr_reader :default_private_key_path

        # Constructor. Determines the OS (attribute @os), applies default
        # data directories accordingly, and determines paths to binaries for SSH
        # and Rsync.
        def initialize()
            @os = case RUBY_PLATFORM
                when /darwin/i then :mac
                when /linux/i then :linux
                when /cygwin/i then :cygwin
                when /mingw/i then :windows
            end
            @user_id = (@os == :windows) ?  ENV['USERNAME'] : ENV['USER']
            @user_home_dir = (@os == :windows) ? ENV['HOMEPATH'] : ENV['HOME']
            @default_private_key_dir =
                File.join(@user_home_dir, '.ssh')
            @default_private_key_path =
                File.join(@default_private_key_dir, 'id_rsa' )
            @rsync_path = `which rsync`.strip
            @ssh_path = `which ssh`.strip
            @usb_volumes_dir =
                case @os
                when :mac
                    '/Volumes'
                when :linux
                    %w(media mnt).select{|d|File.directory?("/#{d}")}[0]  
                when :cygwin
                    '/cygdrive'
                else
                    ''
                end
        end

        # Escape paths as Rsync input on the specific OS
        def rsync_path_escape( path )
            if (@os == :mac)
                # '"' + path + '"'
                path
            else
                # Adapt to other OSs if necessary
                # '"' + path + '"'
                path
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

        # Guess which USB volume should get synchronized.
        # We take the one that contains (some of the) directories that are to
        # be synchronized. If there are more the one with most of the
        # concerned directories is picked.
        def guess_usb_volume( dirs_to_sync )
            volumes = Dir.entries(@usb_volumes_dir).reject do |f|
                f.match(/\.\.?/) 
            end
            volumes.sort_by { |v|
                puts "Checking volume #{v}"
                dirs_to_sync.select{ |dts|
                    File.directory?( File.join(@usb_volumes_dir, usb, dts))
                }.size
            }[0]
        end

    end

end
