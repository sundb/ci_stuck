#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define PORT 6379
#define BUFFER_SIZE 1024

int main() {
    int sock_fd;
    struct sockaddr_in server_addr;
    char buffer[BUFFER_SIZE];
    const char *message = "Hello Server\n";
    ssize_t bytes_received;
    
    // Create socket
    sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_fd == -1) {
        perror("socket");
        exit(EXIT_FAILURE);
    }

    // Set server address
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(PORT);
    server_addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    // Connect to server
    if (connect(sock_fd, (struct sockaddr*)&server_addr, sizeof(server_addr)) == -1) {
        perror("connect");
        close(sock_fd);
        exit(EXIT_FAILURE);
    }
    
    printf("Connected to server on port %d\n", PORT);
    
    // Send message
    if (send(sock_fd, message, strlen(message), 0) == -1) {
        perror("send");
        close(sock_fd);
        exit(EXIT_FAILURE);
    }

    printf("Sent: %s", message);

    // Receive response
    bytes_received = recv(sock_fd, buffer, sizeof(buffer) - 1, 0);
    if (bytes_received == -1) {
        perror("recv");
        close(sock_fd);
        exit(EXIT_FAILURE);
    }

    buffer[bytes_received] = '\0';
    printf("Received: %s", buffer);

    // Close connection
    close(sock_fd);
    printf("Connection closed\n");
    
    return 0;
}
