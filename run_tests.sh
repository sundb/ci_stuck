#!/bin/bash

# Test runner script for epoll_server performance tests

echo "=== Epoll Server Test Suite ==="
echo

# Check if server binary exists
if [ ! -f "./epoll_server" ]; then
    echo "Error: epoll_server binary not found. Please run 'make' first."
    exit 1
fi

# Check if TCL is available
if ! command -v tclsh &> /dev/null; then
    echo "Error: tclsh not found. Please install TCL."
    exit 1
fi

echo "Available tests:"
echo "1. simple_test.tcl    - Single connection, 3M requests"
echo "2. concurrent_test.tcl - Multiple connections, 3M requests"
echo "3. test_performance.tcl - Full performance test suite"
echo

# Function to run a test
run_test() {
    local test_file=$1
    local test_name=$2
    
    echo "========================================="
    echo "Running $test_name"
    echo "========================================="
    
    if [ -f "$test_file" ]; then
        tclsh "$test_file"
        echo
        echo "$test_name completed."
    else
        echo "Error: $test_file not found."
    fi
    
    echo
}

# Check command line argument
if [ $# -eq 1 ]; then
    case $1 in
        "simple"|"1")
            run_test "simple_test.tcl" "Simple Test"
            ;;
        "concurrent"|"2")
            run_test "concurrent_test.tcl" "Concurrent Test"
            ;;
        "performance"|"3")
            run_test "test_performance.tcl" "Performance Test"
            ;;
        "all")
            echo "Running all tests..."
            echo
            run_test "simple_test.tcl" "Simple Test"
            run_test "concurrent_test.tcl" "Concurrent Test"
            run_test "test_performance.tcl" "Performance Test"
            ;;
        *)
            echo "Invalid option: $1"
            echo "Usage: $0 [simple|concurrent|performance|all]"
            exit 1
            ;;
    esac
else
    echo "Usage: $0 [simple|concurrent|performance|all]"
    echo
    echo "Examples:"
    echo "  $0 simple      # Run simple test (single connection)"
    echo "  $0 concurrent  # Run concurrent test (multiple connections)"
    echo "  $0 performance # Run full performance test"
    echo "  $0 all         # Run all tests"
    echo
    echo "Or run tests directly:"
    echo "  tclsh simple_test.tcl"
    echo "  tclsh concurrent_test.tcl"
    echo "  tclsh test_performance.tcl"
fi
