# Epoll Socket Server

这是一个使用epoll的高性能socket服务器，监听6379端口并对所有请求回复"ok"。

## 特性

- 使用epoll进行高效的I/O多路复用
- 非阻塞socket操作
- 边缘触发模式(EPOLLET)
- 支持多个并发连接
- 优雅的信号处理和关闭
- 监听Redis默认端口6379

## 编译和运行

### 编译所有程序
```bash
make all
```

### 只编译服务器
```bash
make epoll_server
```

### 只编译测试客户端
```bash
make test_client
```

### 运行服务器
```bash
make run-server
# 或者直接运行
./epoll_server
```

### 运行测试客户端
```bash
make run-client
# 或者直接运行
./test_client
```

### 自动化测试
```bash
make test
```
这会启动服务器，运行客户端测试，然后停止服务器。

## 使用方法

1. 启动服务器：
   ```bash
   ./epoll_server
   ```
   服务器将在6379端口开始监听。

2. 使用任何TCP客户端连接到服务器：
   ```bash
   telnet localhost 6379
   nc localhost 6379
   redis-cli -p 6379
   ```

3. 发送任何消息，服务器都会回复"ok"。

## 服务器特性说明

- **非阻塞I/O**: 所有socket操作都是非阻塞的
- **Epoll边缘触发**: 使用EPOLLET模式提高性能
- **信号处理**: 支持SIGINT和SIGTERM信号进行优雅关闭
- **错误处理**: 完善的错误处理和资源清理
- **连接管理**: 自动处理客户端连接和断开

## 清理

```bash
make clean
```

## 系统要求

- Linux系统（epoll是Linux特有的）
- GCC编译器
- 标准C库

## 注意事项

- 服务器使用6379端口，确保该端口未被其他程序占用
- 需要在Linux系统上运行（epoll是Linux特有功能）
- 使用Ctrl+C可以优雅地停止服务器
