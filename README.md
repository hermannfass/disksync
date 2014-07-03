disksync
========

Library for data synchronization.

The motivation was to be able to configure external disks, defining from where
to where data synchronization should go, and then allow to synchronize all or
some subdirectories in these locations.

This should allow to build tools that allow calls like 'disk', allowing:

disk push
disk pull
disk push <subdirectory>
disk pull <subdirectory>

Rsync over SSH will be supported.

The project has just started and not supposed to work or to be used at all
now.

