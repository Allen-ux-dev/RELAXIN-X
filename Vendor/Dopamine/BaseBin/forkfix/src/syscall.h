pid_t ffsys_fork(void);

ssize_t ffsys_read(int fildes, void *buf, size_t nbyte);
ssize_t ffsys_write(int fildes, const void *buf, size_t nbyte);
int ffsys_close(int fildes);
