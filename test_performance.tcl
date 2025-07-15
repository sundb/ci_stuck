#!/usr/bin/env tclsh

# Performance test for epoll_server
# Sends 3,000,000 requests and measures performance

set SERVER_HOST "127.0.0.1"
set SERVER_PORT 6379
set NUM_REQUESTS 3000000
set NUM_CONNECTIONS 100
set REQUESTS_PER_CONNECTION [expr $NUM_REQUESTS / $NUM_CONNECTIONS]

proc log_message {msg} {
    puts "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $msg"
}

proc start_server {} {
    global server_pid
    
    log_message "Starting epoll_server..."
    
    # Start server in background
    set server_pid [exec ./epoll_server &]
    
    # Wait a bit for server to start
    after 1000
    
    # Check if server is running
    if {[catch {socket $::SERVER_HOST $::SERVER_PORT} sock]} {
        error "Failed to connect to server: $sock"
    }
    close $sock
    
    log_message "Server started successfully (PID: $server_pid)"
}

proc stop_server {} {
    global server_pid
    
    if {[info exists server_pid]} {
        log_message "Stopping server (PID: $server_pid)..."
        catch {exec kill $server_pid}
        after 500
        catch {exec kill -9 $server_pid}
    }
}

proc create_connections {num_connections} {
    set connections {}
    
    log_message "Creating $num_connections connections..."
    
    for {set i 0} {$i < $num_connections} {incr i} {
        if {[catch {socket $::SERVER_HOST $::SERVER_PORT} sock]} {
            error "Failed to create connection $i: $sock"
        }
        
        # Set socket to non-blocking mode for writing
        fconfigure $sock -blocking 0 -buffering none
        
        lappend connections $sock
        
        if {($i + 1) % 10 == 0} {
            log_message "Created [expr $i + 1] connections..."
        }
    }
    
    log_message "All $num_connections connections created successfully"
    return $connections
}

proc send_requests {connections requests_per_conn} {
    set total_sent 0
    set message "test request\n"
    
    log_message "Starting to send [expr $requests_per_conn * [llength $connections]] requests..."
    set start_time [clock milliseconds]
    
    # Send all requests first, don't read responses yet
    for {set req 0} {$req < $requests_per_conn} {incr req} {
        foreach sock $connections {
            if {[catch {puts -nonewline $sock $message} err]} {
                log_message "Error sending request: $err"
                continue
            }
            incr total_sent
        }
        
        # Log progress every 10000 requests
        if {($req + 1) % 10000 == 0} {
            set elapsed [expr [clock milliseconds] - $start_time]
            set rate [expr ($total_sent * 1000.0) / $elapsed]
            log_message "Sent [expr $req + 1] batches ($total_sent requests), rate: [format %.1f $rate] req/sec"
        }
    }
    
    set send_time [expr [clock milliseconds] - $start_time]
    set send_rate [expr ($total_sent * 1000.0) / $send_time]
    
    log_message "Finished sending $total_sent requests in ${send_time}ms (rate: [format %.1f $send_rate] req/sec)"
    
    return [list $total_sent $send_time]
}

proc read_responses {connections expected_responses} {
    set total_received 0
    set expected_response "ok\r\n"
    
    log_message "Starting to read $expected_responses responses..."
    set start_time [clock milliseconds]
    
    # Set all sockets to blocking mode for reading
    foreach sock $connections {
        fconfigure $sock -blocking 1
    }
    
    # Read responses
    set responses_per_conn [expr $expected_responses / [llength $connections]]
    
    for {set req 0} {$req < $responses_per_conn} {incr req} {
        foreach sock $connections {
            if {[catch {gets $sock response} bytes_read]} {
                log_message "Error reading response: $bytes_read"
                continue
            }
            
            if {$bytes_read >= 0} {
                if {$response ne "ok"} {
                    log_message "Unexpected response: '$response'"
                }
                incr total_received
            }
        }
        
        # Log progress every 10000 responses
        if {($req + 1) % 10000 == 0} {
            set elapsed [expr [clock milliseconds] - $start_time]
            set rate [expr ($total_received * 1000.0) / $elapsed]
            log_message "Read [expr $req + 1] batches ($total_received responses), rate: [format %.1f $rate] resp/sec"
        }
    }
    
    set read_time [expr [clock milliseconds] - $start_time]
    set read_rate [expr ($total_received * 1000.0) / $read_time]
    
    log_message "Finished reading $total_received responses in ${read_time}ms (rate: [format %.1f $read_rate] resp/sec)"
    
    return [list $total_received $read_time]
}

proc close_connections {connections} {
    log_message "Closing [llength $connections] connections..."
    
    foreach sock $connections {
        catch {close $sock}
    }
    
    log_message "All connections closed"
}

proc run_performance_test {} {
    global NUM_CONNECTIONS REQUESTS_PER_CONNECTION
    
    log_message "=== Epoll Server Performance Test ==="
    log_message "Total requests: $::NUM_REQUESTS"
    log_message "Connections: $NUM_CONNECTIONS"
    log_message "Requests per connection: $REQUESTS_PER_CONNECTION"
    log_message "========================================="
    
    set overall_start [clock milliseconds]
    
    # Start server
    start_server
    
    # Create connections
    set connections [create_connections $NUM_CONNECTIONS]
    
    # Send all requests first
    lassign [send_requests $connections $REQUESTS_PER_CONNECTION] total_sent send_time
    
    # Then read all responses
    lassign [read_responses $connections $total_sent] total_received read_time
    
    # Close connections
    close_connections $connections
    
    # Stop server
    stop_server
    
    set overall_time [expr [clock milliseconds] - $overall_start]
    set overall_rate [expr ($total_sent * 1000.0) / $overall_time]
    
    log_message "========================================="
    log_message "=== Performance Test Results ==="
    log_message "Total requests sent: $total_sent"
    log_message "Total responses received: $total_received"
    log_message "Send time: ${send_time}ms"
    log_message "Read time: ${read_time}ms"
    log_message "Overall time: ${overall_time}ms"
    log_message "Overall throughput: [format %.1f $overall_rate] req/sec"
    log_message "Success rate: [format %.2f [expr ($total_received * 100.0) / $total_sent]]%"
    log_message "================================="
}

# Handle Ctrl+C gracefully
proc cleanup {} {
    global connections
    
    log_message "Received interrupt signal, cleaning up..."
    
    if {[info exists connections]} {
        close_connections $connections
    }
    
    stop_server
    exit 0
}

signal trap SIGINT cleanup
signal trap SIGTERM cleanup

# Run the test
if {[catch {run_performance_test} error]} {
    log_message "Error during test: $error"
    cleanup
    exit 1
}

log_message "Performance test completed successfully"
exit 0
