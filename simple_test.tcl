#!/usr/bin/env tclsh

# Simple test: Send 3,000,000 requests, then read all responses
# This version focuses on your specific requirement

set SERVER_HOST "127.0.0.1"
set SERVER_PORT 6379
set NUM_REQUESTS 3000000

proc log_msg {msg} {
    puts "[clock format [clock seconds] -format {%H:%M:%S}] $msg"
    flush stdout
}

proc start_server {} {
    log_msg "Starting epoll_server..."
    
    # Start server in background
    set server_pid [exec ./epoll_server &]
    
    # Wait for server to start
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

proc run_test {} {
    global NUM_REQUESTS SERVER_HOST SERVER_PORT
    
    log_msg "=== Starting Test: $NUM_REQUESTS requests ==="
    
    # Start server
    set server_pid [start_server]
    
    # Create socket connection
    log_msg "Creating connection to ${SERVER_HOST}:${SERVER_PORT}..."
    set sock [socket $SERVER_HOST $SERVER_PORT]
    fconfigure $sock -blocking 0 -buffering none
    
    # Phase 1: Send all requests without reading responses
    log_msg "Phase 1: Sending $NUM_REQUESTS requests..."
    set send_start [clock milliseconds]
    set message "test\n"
    
    for {set i 0} {$i < $NUM_REQUESTS} {incr i} {
        # Send request
        if {[catch {puts -nonewline $sock $message} err]} {
            log_msg "Error sending request $i: $err"
            break
        }
        
        # Progress logging
        if {($i + 1) % 100000 == 0} {
            set elapsed [expr [clock milliseconds] - $send_start]
            set rate [expr (($i + 1) * 1000.0) / $elapsed]
            log_msg "Sent [expr $i + 1] requests, rate: [format %.0f $rate] req/sec"
        }
    }
    
    set send_time [expr [clock milliseconds] - $send_start]
    set send_rate [expr ($NUM_REQUESTS * 1000.0) / $send_time]
    log_msg "Phase 1 complete: Sent $NUM_REQUESTS requests in ${send_time}ms ([format %.0f $send_rate] req/sec)"
    
    # Phase 2: Read all responses
    log_msg "Phase 2: Reading $NUM_REQUESTS responses..."
    fconfigure $sock -blocking 1  ;# Switch to blocking mode for reading
    
    set read_start [clock milliseconds]
    set responses_received 0
    
    for {set i 0} {$i < $NUM_REQUESTS} {incr i} {
        if {[catch {gets $sock response} bytes]} {
            log_msg "Error reading response $i: $bytes"
            break
        }
        
        if {$bytes >= 0} {
            incr responses_received
            
            # Verify response
            if {$response ne "ok"} {
                log_msg "Unexpected response at $i: '$response'"
            }
        }
        
        # Progress logging
        if {($i + 1) % 100000 == 0} {
            set elapsed [expr [clock milliseconds] - $read_start]
            set rate [expr (($i + 1) * 1000.0) / $elapsed]
            log_msg "Read [expr $i + 1] responses, rate: [format %.0f $rate] resp/sec"
        }
    }
    
    set read_time [expr [clock milliseconds] - $read_start]
    set read_rate [expr ($responses_received * 1000.0) / $read_time]
    
    # Close connection
    close $sock
    
    # Stop server
    stop_server $server_pid
    
    # Results
    set total_time [expr $send_time + $read_time]
    set overall_rate [expr ($NUM_REQUESTS * 1000.0) / $total_time]
    
    log_msg "=== Test Results ==="
    log_msg "Requests sent: $NUM_REQUESTS"
    log_msg "Responses received: $responses_received"
    log_msg "Send time: ${send_time}ms ([format %.0f $send_rate] req/sec)"
    log_msg "Read time: ${read_time}ms ([format %.0f $read_rate] resp/sec)"
    log_msg "Total time: ${total_time}ms ([format %.0f $overall_rate] req/sec)"
    log_msg "Success rate: [format %.2f [expr ($responses_received * 100.0) / $NUM_REQUESTS]]%"
    log_msg "==================="
}

# Handle interrupts
proc cleanup {} {
    global server_pid sock
    
    log_msg "Cleaning up..."
    
    if {[info exists sock]} {
        catch {close $sock}
    }
    
    if {[info exists server_pid]} {
        stop_server $server_pid
    }
    
    exit 0
}

# Set up signal handlers (if available)
if {![catch {package require Tclx}]} {
    signal trap SIGINT cleanup
    signal trap SIGTERM cleanup
}

# Run the test
if {[catch {run_test} error]} {
    log_msg "Test failed: $error"
    cleanup
    exit 1
}

log_msg "Test completed successfully"
exit 0
