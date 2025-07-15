#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>

#define PORT 6379
#define MAX_EVENTS 1024
#define BUFFER_SIZE 1024

// Set socket to non-blocking mode
int set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags == -1) {
        perror("fcntl F_GETFL");
        return -1;
    }
    
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
        perror("fcntl F_SETFL");
        return -1;
    }
    
    return 0;
}

// Create and bind listening socket
int create_listen_socket() {
    int listen_fd;
    struct sockaddr_in server_addr;
    int opt = 1;
    
    // Create socket
    listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd == -1) {
        perror("socket");
        return -1;
    }

    // Set socket options, allow address reuse
    if (setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) == -1) {
        perror("setsockopt");
        close(listen_fd);
        return -1;
    }

    // Set to non-blocking
    if (set_nonblocking(listen_fd) == -1) {
        close(listen_fd);
        return -1;
    }

    // Bind address
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(PORT);
    
    if (bind(listen_fd, (struct sockaddr*)&server_addr, sizeof(server_addr)) == -1) {
        perror("bind");
        close(listen_fd);
        return -1;
    }
    
    // Start listening
    if (listen(listen_fd, SOMAXCONN) == -1) {
        perror("listen");
        close(listen_fd);
        return -1;
    }
    
    printf("Server listening on port %d\n", PORT);
    return listen_fd;
}

// Handle new connection
int handle_new_connection(int listen_fd, int epoll_fd) {
    struct sockaddr_in client_addr;
    socklen_t client_len = sizeof(client_addr);
    int client_fd;
    struct epoll_event event;
    
    client_fd = accept(listen_fd, (struct sockaddr*)&client_addr, &client_len);
    if (client_fd == -1) {
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
            perror("accept");
        }
        return -1;
    }
    
    printf("New connection from %s:%d\n", 
           inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));
    
    // Set client socket to non-blocking
    if (set_nonblocking(client_fd) == -1) {
        close(client_fd);
        return -1;
    }

    // Add client socket to epoll
    event.events = EPOLLIN | EPOLLET; // Edge-triggered mode
    event.data.fd = client_fd;
    if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, client_fd, &event) == -1) {
        perror("epoll_ctl: client_fd");
        close(client_fd);
        return -1;
    }
    
    return 0;
}

// Handle client data
static int msg_count = 0;
int handle_client_data(int client_fd) {
    static char client_buffers[1024][BUFFER_SIZE * 2]; // Buffer for each client
    static int buffer_lens[1024] = {0}; // Track buffer length for each client
    char buffer[BUFFER_SIZE];
    ssize_t bytes_read;
    const char *response = "ok\r\n";
    char *msg_start, *msg_end;
    int client_idx = client_fd % 1024; // Simple mapping
    
    while (1) {
        bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
        
        if (bytes_read == -1) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                break;
            } else {
                perror("read");
                return -1;
            }
        } else if (bytes_read == 0) {
            printf("Client disconnected (fd: %d)\n", client_fd);
            buffer_lens[client_idx] = 0; // Reset buffer
            return -1;
        } else {
            // Append to client buffer
            if (buffer_lens[client_idx] + bytes_read < sizeof(client_buffers[client_idx])) {
                memcpy(client_buffers[client_idx] + buffer_lens[client_idx], buffer, bytes_read);
                buffer_lens[client_idx] += bytes_read;
                client_buffers[client_idx][buffer_lens[client_idx]] = '\0';
            }
            
            // Process complete messages ending with \r\n
            msg_start = client_buffers[client_idx];
            while ((msg_end = strstr(msg_start, "\r\n")) != NULL) {
                // Found complete message
                *msg_end = '\0'; // Temporarily null-terminate
                // printf("Received message from client (fd: %d): %s, %d\n", client_fd, msg_start, msg_count++);
                
                // Send response
                if (write(client_fd, response, strlen(response)) == -1) {
                    perror("write");
                    return -1;
                }
                
                // Move to next message
                msg_start = msg_end + 2; // Skip \r\n
            }
            
            // Move remaining data to beginning of buffer
            int remaining = strlen(msg_start);
            if (remaining > 0) {
                memmove(client_buffers[client_idx], msg_start, remaining);
            }
            buffer_lens[client_idx] = remaining;
            client_buffers[client_idx][remaining] = '\0';
        }
    }
    
    return 0;
}

// Signal handler function
volatile sig_atomic_t running = 1;
void signal_handler(int sig) {
    running = 0;
    printf("\nReceived signal %d, shutting down...\n", sig);
}

int main() {
    int listen_fd, epoll_fd;
    struct epoll_event events[MAX_EVENTS];
    int nfds, i;
    
    // Set up signal handling
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // Create listening socket
    listen_fd = create_listen_socket();
    if (listen_fd == -1) {
        exit(EXIT_FAILURE);
    }

    // Create epoll instance
    epoll_fd = epoll_create1(0);
    if (epoll_fd == -1) {
        perror("epoll_create1");
        close(listen_fd);
        exit(EXIT_FAILURE);
    }

    // Add listening socket to epoll
    struct epoll_event event;
    event.events = EPOLLIN;
    event.data.fd = listen_fd;
    if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, listen_fd, &event) == -1) {
        perror("epoll_ctl: listen_fd");
        close(listen_fd);
        close(epoll_fd);
        exit(EXIT_FAILURE);
    }
    
    printf("Epoll server started successfully\n");
    
    // Main event loop
    while (running) {
        nfds = epoll_wait(epoll_fd, events, MAX_EVENTS, 1000); // 1 second timeout

        if (nfds == -1) {
            if (errno == EINTR) {
                continue; // Interrupted by signal, continue
            }
            perror("epoll_wait");
            break;
        }

        for (i = 0; i < nfds; i++) {
            if (events[i].data.fd == listen_fd) {
                // New connection
                handle_new_connection(listen_fd, epoll_fd);
            } else {
                // Client data
                if (handle_client_data(events[i].data.fd) == -1) {
                    // Client disconnected or error, remove from epoll
                    epoll_ctl(epoll_fd, EPOLL_CTL_DEL, events[i].data.fd, NULL);
                    close(events[i].data.fd);
                }
            }
        }
    }
    
    // Clean up resources
    close(listen_fd);
    close(epoll_fd);
    printf("Server shutdown complete\n");
    
    return 0;
}
