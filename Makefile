CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -O2
SERVER_TARGET = epoll_server
CLIENT_TARGET = test_client
SERVER_SOURCE = epoll_server.c
CLIENT_SOURCE = test_client.c

all: $(SERVER_TARGET) $(CLIENT_TARGET)

$(SERVER_TARGET): $(SERVER_SOURCE)
	$(CC) $(CFLAGS) -o $(SERVER_TARGET) $(SERVER_SOURCE)

$(CLIENT_TARGET): $(CLIENT_SOURCE)
	$(CC) $(CFLAGS) -o $(CLIENT_TARGET) $(CLIENT_SOURCE)

clean:
	rm -f $(SERVER_TARGET) $(CLIENT_TARGET)

run-server: $(SERVER_TARGET)
	./$(SERVER_TARGET)

run-client: $(CLIENT_TARGET)
	./$(CLIENT_TARGET)

test: $(SERVER_TARGET) $(CLIENT_TARGET)
	@echo "Starting server in background..."
	@./$(SERVER_TARGET) &
	@sleep 1
	@echo "Running client test..."
	@./$(CLIENT_TARGET)
	@echo "Stopping server..."
	@pkill -f $(SERVER_TARGET) || true

.PHONY: all clean run-server run-client test
