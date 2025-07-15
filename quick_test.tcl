#!/usr/bin/env tclsh

# Quick test with smaller number of requests to verify functionality

set SERVER_HOST "127.0.0.1"
set SERVER_PORT 6379
set NUM_REQUESTS 3000000

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
}

proc run_quick_test {} {
    global NUM_REQUESTS SERVER_HOST SERVER_PORT
    
    log_msg "=== Quick Test: $NUM_REQUESTS requests ==="
    
    # Start server
    set server_pid [start_server]
    
    # Create connection
    log_msg "Creating connection..."
    set sock [socket $SERVER_HOST $SERVER_PORT]
    fconfigure $sock -blocking 0 -buffering none
    
    # Phase 1: Send all requests
    log_msg "Phase 1: Sending $NUM_REQUESTS requests..."
    set send_start [clock milliseconds]
    set message "test\n"
    
    for {set i 0} {$i < $NUM_REQUESTS} {incr i} {
        if {[catch {puts -nonewline $sock $message} err]} {
            log_msg "Error sending request $i: $err"
            break
        }
    }
    
    set send_time [expr [clock milliseconds] - $send_start]
    log_msg "Phase 1 complete: Sent $NUM_REQUESTS requests in ${send_time}ms"
    
    # Phase 2: Read all responses
    log_msg "Phase 2: Reading responses..."
    fconfigure $sock -blocking 1

    set read_start [clock milliseconds]
    set responses_received 0

    set response ""
    
    while {$responses_received < $NUM_REQUESTS} {
        if {[catch {read $sock 10} data]} {
            log_msg "Error reading response: $data"
            break
        }

        if {[string length $data] > 0} {
            append response $data
            
            # Process all complete "ok\r\n" responses in buffer
            # set response "ok\r\n"
            while {[string first "ok\n" $response] == 0} {
                incr responses_received
                puts $responses_received
                set response [string range $response 3 end]  ;# Remove "ok\r\n" from front
                
                puts $responses_received
                if {$responses_received >= $NUM_REQUESTS} {
                    break
                }
            }
        } elseif {[string length $data] == 0} {
            # No more data available, but socket still open
            after 1  ;# Small delay to avoid busy waiting
        }
    }
    
    set read_time [expr [clock milliseconds] - $read_start]
    
    # Cleanup
    close $sock
    stop_server $server_pid
    
    # Results
    log_msg "=== Results ==="
    log_msg "Sent: $NUM_REQUESTS"
    log_msg "Received: $responses_received"
    log_msg "Send time: ${send_time}ms"
    log_msg "Read time: ${read_time}ms"
    log_msg "Success rate: [format %.2f [expr ($responses_received * 100.0) / $NUM_REQUESTS]]%"
    log_msg "=============="
}

# Run the test
if {[catch {run_quick_test} error]} {
    log_msg "Test failed: $error"
    exit 1
}

log_msg "Quick test completed successfully"
exit 0
