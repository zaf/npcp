# Learning Nim

# npcp
Parallel file copy

Usage: `npcp [-f] source destination`

The number of parallel threads is by default the number of available CPU threads.
To change this set the enviroment variable PCP_THREADS with the desired number of threads:
`PCP_THREADS=4 npcp [source] [destination]`

To enable syncing of data on disk set the enviroment variable PCP_SYNC to true:
`PCP_SYNC=true npcp [source] [destination]`
