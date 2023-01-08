# npcp
## Parallel file copy

### Usage:
`npcp [options] source destination`

### Description:
The npcp utility copies the contents of the source file to the destination file.
It maps the contets of the files in memory and copies data in parallel using
a number of threads that by default is the number of available CPU threads.

### Options:

**-f, --force:** Overwrite destination file if it exists.

**-s, --sync:** Sync file to disk after done copying data.

**-t=[threads], --threads=[threads]:** Specifies the number of threads used
to copy data simultaneously. This number is by default the number of available CPU threads.

----

### Installation:
To build:

    `nim build`

For more options:

    `nim help`