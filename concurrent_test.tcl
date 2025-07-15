#!/usr/bin/env tclsh

# Concurrent test with multiple connections
# Send 3,000,000 requests using multiple connections for better performance

set SERVER_HOST "127.0.0.1"
set SERVER_PORT 6379
set NUM_REQUESTS 3000000
set NUM_CONNECTIONS 50
set REQUESTS_PER_CONN [expr $NUM_REQUESTS / $NUM_CONNECTIONS]

proc log_msg {msg} {
    puts "[clock format [clock seconds] -format {%H:%M:%S}] $msg"
    flush stdout
}

proc start_server {} {
    log_msg "Starting epoll_server..."
    
    set server_pid [exec ./epoll_server &]
    after 2000
    
    # Test connection
    if {[catch {socket $::SERVER_HOST $::SERVER_PORT} test_sock]} {
        error "Cannot connect to server: $test_sock"
    }
    close $test_sock
    
    log_msg "Server started successfully"
    return $server_pid
}

proc stop_server {pid} {
    log_msg "Stopping server..."
    catch {exec kill $pid}
    after 500
    catch {exec kill -9 $pid}
}

proc create_connections {num_conn} {
    global SERVER_HOST SERVER_PORT
    
    log_msg "Creating $num_conn connections..."
    set connections {}
    
    for {set i 0} {$i < $num_conn} {incr i} {
        if {[catch {socket $SERVER_HOST $SERVER_PORT} sock]} {
            error "Failed to create connection $i: $sock"
        }
        
        fconfigure $sock -blocking 0 -buffering none
        lappend connections $sock
        
        if {($i + 1) % 10 == 0} {
            log_msg "Created [expr $i + 1]/$num_conn connections"
        }
    }
    
    log_msg "All $num_conn connections created"
    return $connections
}

proc send_all_requests {connections requests_per_conn} {
    set total_sent 0
    set message "test\n"
    
    log_msg "Phase 1: Sending [expr $requests_per_conn * [llength $connections]] requests..."
    set start_time [clock milliseconds]
    
    # Send all requests first - don't read responses yet
    for {set req 0} {$req < $requests_per_conn} {incr req} {
        foreach sock $connections {
            if {[catch {puts -nonewline $sock $message} err]} {
                log_msg "Send error: $err"
                continue
            }
            incr total_sent
        }
        
        # Progress update
        if {($req + 1) % 5000 == 0} {
            set elapsed [expr [clock milliseconds] - $start_time]
            set rate [expr ($total_sent * 1000.0) / $elapsed]
            log_msg "Sent [expr $req + 1] batches ($total_sent requests), rate: [format %.0f $rate] req/sec"
        }
    }
    
    set send_time [expr [clock milliseconds] - $start_time]
    set send_rate [expr ($total_sent * 1000.0) / $send_time]
    
    log_msg "Phase 1 complete: Sent $total_sent requests in ${send_time}ms ([format %.0f $send_rate] req/sec)"
    
    return [list $total_sent $send_time]
}

proc read_all_responses {connections expected_responses} {
    set total_received 0
    
    log_msg "Phase 2: Reading $expected_responses responses..."
    set start_time [clock milliseconds]
    
    # Switch all connections to blocking mode for reading
    foreach sock $connections {
        fconfigure $sock -blocking 1
    }
    
    set responses_per_conn [expr $expected_responses / [llength $connections]]
    
    for {set req 0} {$req < $responses_per_conn} {incr req} {
        foreach sock $connections {
            if {[catch {gets $sock response} bytes]} {
                log_msg "Read error: $bytes"
                continue
            }
            
            if {$bytes >= 0} {
                if {$response ne "ok"} {
                    log_msg "Unexpected response: '$response'"
                }
                incr total_received
            }
        }
        
        # Progress update
        if {($req + 1) % 5000 == 0} {
            set elapsed [expr [clock milliseconds] - $start_time]
            set rate [expr ($total_received * 1000.0) / $elapsed]
            log_msg "Read [expr $req + 1] batches ($total_received responses), rate: [format %.0f $rate] resp/sec"
        }
    }
    
    set read_time [expr [clock milliseconds] - $start_time]
    set read_rate [expr ($total_received * 1000.0) / $read_time]
    
    log_msg "Phase 2 complete: Read $total_received responses in ${read_time}ms ([format %.0f $read_rate] resp/sec)"
    
    return [list $total_received $read_time]
}

proc close_connections {connections} {
    log_msg "Closing [llength $connections] connections..."
    foreach sock $connections {
        catch {close $sock}
    }
}

proc run_concurrent_test {} {
    global NUM_REQUESTS NUM_CONNECTIONS REQUESTS_PER_CONN
    
    log_msg "=== Concurrent Test Configuration ==="
    log_msg "Total requests: $NUM_REQUESTS"
    log_msg "Connections: $NUM_CONNECTIONS"
    log_msg "Requests per connection: $REQUESTS_PER_CONN"
    log_msg "=================================="
    
    set overall_start [clock milliseconds]
    
    # Start server
    set server_pid [start_server]
    
    # Create connections
    set connections [create_connections $NUM_CONNECTIONS]
    
    # Phase 1: Send all requests
    lassign [send_all_requests $connections $REQUESTS_PER_CONN] total_sent send_time
    
    # Phase 2: Read all responses
    lassign [read_all_responses $connections $total_sent] total_received read_time
    
    # Cleanup
    close_connections $connections
    stop_server $server_pid
    
    # Final results
    set overall_time [expr [clock milliseconds] - $overall_start]
    set overall_rate [expr ($total_sent * 1000.0) / $overall_time]
    
    log_msg "=== Final Results ==="
    log_msg "Requests sent: $total_sent"
    log_msg "Responses received: $total_received"
    log_msg "Send time: ${send_time}ms"
    log_msg "Read time: ${read_time}ms"
    log_msg "Overall time: ${overall_time}ms"
    log_msg "Overall throughput: [format %.0f $overall_rate] req/sec"
    log_msg "Success rate: [format %.2f [expr ($total_received * 100.0) / $total_sent]]%"
    log_msg "===================="
}

# Cleanup function
proc cleanup {} {
    global server_pid connections
    
    log_msg "Cleaning up..."
    
    if {[info exists connections]} {
        close_connections $connections
    }
    
    if {[info exists server_pid]} {
        stop_server $server_pid
    }
    
    exit 0
}

# Set up signal handlers if available
if {![catch {package require Tclx}]} {
    signal trap SIGINT cleanup
    signal trap SIGTERM cleanup
}

# Run the test
if {[catch {run_concurrent_test} error]} {
    log_msg "Test failed: $error"
    cleanup
    exit 1
}

log_msg "Concurrent test completed successfully"
exit 0
