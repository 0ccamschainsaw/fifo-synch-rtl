`timescale 1ns / 1ps

module sync_fifo_tb #(
    parameter integer DEPTH = 8,
    parameter integer DATAW = 8
);
    logic clk = 1'b0;
    always #5 clk = ~clk;

    sync_fifo_if #(.DATAW(DATAW)) fifo_if(clk);

    sync_fifo #(.DEPTH(DEPTH), .DATAW(DATAW)) dut (
        .clk(clk),
        .rstn(fifo_if.rstn),
        .w_en(fifo_if.w_en),
        .r_en(fifo_if.r_en),
        .data_in(fifo_if.data_in),
        .data_out(fifo_if.data_out),
        .full(fifo_if.full),
        .empty(fifo_if.empty)
    );

    logic [DATAW-1:0] model[$];
    integer model_count = 0;
    integer errors = 0;
    integer accepted_writes = 0;
    integer accepted_reads = 0;
    integer empty_bin = 0;
    integer one_bin = 0;
    integer middle_bin = 0;
    integer almost_full_bin = 0;
    integer full_bin = 0;
    integer write_while_full = 0;
    integer read_while_empty = 0;
    integer simultaneous_empty = 0;
    integer simultaneous_middle = 0;
    integer simultaneous_full = 0;
    integer write_wraps = 0;
    integer read_wraps = 0;
    integer write_pointer = 0;
    integer read_pointer = 0;
    integer pending_read = 0;
    logic [DATAW-1:0] expected_read;
    integer seed_value = 1;
    integer random_seed = 1;
    integer random_value;
    integer single_test = 0;
    string selected_test = "all";

    sync_fifo_model_sva #(.DEPTH(DEPTH)) model_checks (
        .clk(clk),
        .rstn(fifo_if.rstn),
        .model_count(model_count),
        .full(fifo_if.full),
        .empty(fifo_if.empty)
    );

    always @(fifo_if.monitor_cb) begin
        if (!fifo_if.monitor_cb.rstn) begin
            model.delete();
            model_count = 0;
            pending_read = 0;
            write_pointer = 0;
            read_pointer = 0;
        end else begin
            if (pending_read) begin
                if (fifo_if.monitor_cb.data_out !== expected_read) begin
                    $display("SCOREBOARD ERROR at %0t: expected %0h, got %0h",
                             $time, expected_read, fifo_if.monitor_cb.data_out);
                    errors = errors + 1;
                end
                pending_read = 0;
            end

            if (model_count == 0)
                empty_bin = empty_bin + 1;
            if (model_count == 1)
                one_bin = one_bin + 1;
            if ((DEPTH > 3) && (model_count > 1) &&
                (model_count < DEPTH - 1))
                middle_bin = middle_bin + 1;
            if (model_count == DEPTH - 1)
                almost_full_bin = almost_full_bin + 1;
            if (model_count == DEPTH)
                full_bin = full_bin + 1;

            if (fifo_if.monitor_cb.w_en && fifo_if.monitor_cb.full)
                write_while_full = write_while_full + 1;
            if (fifo_if.monitor_cb.r_en && fifo_if.monitor_cb.empty)
                read_while_empty = read_while_empty + 1;
            if (fifo_if.monitor_cb.w_en && fifo_if.monitor_cb.r_en) begin
                if (model_count == 0)
                    simultaneous_empty = simultaneous_empty + 1;
                else if (model_count == DEPTH)
                    simultaneous_full = simultaneous_full + 1;
                else
                    simultaneous_middle = simultaneous_middle + 1;
            end

            if (fifo_if.monitor_cb.r_en && !fifo_if.monitor_cb.empty) begin
                if (model.size() == 0) begin
                    $display("SCOREBOARD ERROR at %0t: accepted read from empty model",
                             $time);
                    errors = errors + 1;
                end else begin
                    expected_read = model.pop_front();
                    pending_read = 1;
                    accepted_reads = accepted_reads + 1;
                end
                if (read_pointer == DEPTH - 1) begin
                    read_pointer = 0;
                    read_wraps = read_wraps + 1;
                end else begin
                    read_pointer = read_pointer + 1;
                end
            end

            if (fifo_if.monitor_cb.w_en && !fifo_if.monitor_cb.full) begin
                model.push_back(fifo_if.monitor_cb.data_in);
                accepted_writes = accepted_writes + 1;
                if (write_pointer == DEPTH - 1) begin
                    write_pointer = 0;
                    write_wraps = write_wraps + 1;
                end else begin
                    write_pointer = write_pointer + 1;
                end
            end

            model_count = model.size();
            #1;
            if ((model_count != model.size()) ||
                (fifo_if.full !== (model_count == DEPTH)) ||
                (fifo_if.empty !== (model_count == 0))) begin
                $display("SCOREBOARD ERROR at %0t: model count=%0d full=%b empty=%b",
                         $time, model_count, fifo_if.full, fifo_if.empty);
                errors = errors + 1;
            end
        end
    end

    task automatic drive_cycle(
        input logic write_request,
        input logic read_request,
        input logic [DATAW-1:0] value
    );
        @(fifo_if.cb);
        fifo_if.cb.w_en <= write_request;
        fifo_if.cb.r_en <= read_request;
        fifo_if.cb.data_in <= value;
    endtask

    task automatic settle;
        drive_cycle(1'b0, 1'b0, '0);
        repeat (2) @(posedge clk);
    endtask

    task automatic reset_fifo;
        @(negedge clk);
        fifo_if.rstn = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        fifo_if.rstn = 1'b1;
        repeat (2) @(posedge clk);
    endtask

    task automatic write_items(input integer count);
        integer index;
        begin
            for (index = 0; index < count; index = index + 1)
                drive_cycle(1'b1, 1'b0, DATAW'(index + 1));
            settle();
        end
    endtask

    task automatic read_items(input integer count);
        integer index;
        begin
            for (index = 0; index < count; index = index + 1)
                drive_cycle(1'b0, 1'b1, '0);
            settle();
        end
    endtask

    task automatic test_reset;
        begin
            reset_fifo();
            settle();
            if (!fifo_if.empty || fifo_if.full || $isunknown(fifo_if.data_out)) begin
                $display("SCOREBOARD ERROR: reset state is invalid");
                errors = errors + 1;
            end
        end
    endtask

    task automatic test_fill_to_full;
        begin
            write_items(DEPTH);
            if (!fifo_if.full) begin
                $display("SCOREBOARD ERROR: FIFO did not fill at DEPTH writes");
                errors = errors + 1;
            end
        end
    endtask

    task automatic test_drain_to_empty;
        begin
            write_items(DEPTH);
            read_items(DEPTH);
            if (!fifo_if.empty) begin
                $display("SCOREBOARD ERROR: FIFO did not empty at DEPTH reads");
                errors = errors + 1;
            end
        end
    endtask

    task automatic test_overflow_attempt;
        begin
            write_items(DEPTH + 2);
            if (!fifo_if.full) begin
                $display("SCOREBOARD ERROR: overflow attempt changed full state");
                errors = errors + 1;
            end
            read_items(DEPTH);
            if (!fifo_if.empty) begin
                $display("SCOREBOARD ERROR: overflow corrupted FIFO occupancy");
                errors = errors + 1;
            end
        end
    endtask

    task automatic test_underflow_attempt;
        begin
            read_items(2);
            if (!fifo_if.empty) begin
                $display("SCOREBOARD ERROR: underflow attempt changed empty state");
                errors = errors + 1;
            end
            if (fifo_if.data_out !== '0) begin
                $display("SCOREBOARD ERROR: underflow attempt changed data_out");
                errors = errors + 1;
            end
            write_items(1);
            read_items(1);
        end
    endtask

    task automatic test_simul_rw_mid;
        begin
            write_items((DEPTH > 2) ? 2 : 1);
            drive_cycle(1'b1, 1'b1, DATAW'(8'hA5));
            settle();
            read_items((DEPTH > 2) ? 2 : 1);
        end
    endtask

    task automatic test_simul_rw_full;
        begin
            write_items(DEPTH);
            drive_cycle(1'b1, 1'b1, DATAW'(8'h5A));
            settle();
            read_items(DEPTH - 1);
        end
    endtask

    task automatic test_simul_rw_empty;
        begin
            drive_cycle(1'b1, 1'b1, DATAW'(8'hC3));
            settle();
            read_items(1);
        end
    endtask

    task automatic test_wraparound;
        integer index;
        begin
            for (index = 0; index < (DEPTH * 4); index = index + 1) begin
                drive_cycle(1'b1, 1'b0, DATAW'(index));
                drive_cycle(1'b0, 1'b1, '0);
            end
            settle();
        end
    endtask

    task automatic run_random(input integer cycles, input integer write_percent,
                              input integer read_percent);
        integer index;
        logic write_request;
        logic read_request;
        begin
            for (index = 0; index < cycles; index = index + 1) begin
                random_value = $urandom_range(0, 99);
                write_request = (random_value < write_percent);
                random_value = $urandom_range(0, 99);
                read_request = (random_value < read_percent);
                drive_cycle(write_request, read_request, DATAW'($urandom));
            end
            settle();
        end
    endtask

    task automatic test_reset_mid_traffic;
        begin
            write_items((DEPTH > 1) ? 2 : 1);
            reset_fifo();
            settle();
            if (!fifo_if.empty || fifo_if.full) begin
                $display("SCOREBOARD ERROR: mid-traffic reset did not flush FIFO");
                errors = errors + 1;
            end
            write_items(1);
            read_items(1);
        end
    endtask

    task automatic run_named_test(input string test_name);
        begin
            reset_fifo();
            if (test_name == "reset")
                test_reset();
            else if (test_name == "fill_to_full")
                test_fill_to_full();
            else if (test_name == "drain_to_empty")
                test_drain_to_empty();
            else if (test_name == "overflow_attempt")
                test_overflow_attempt();
            else if (test_name == "underflow_attempt")
                test_underflow_attempt();
            else if (test_name == "simul_rw_mid")
                test_simul_rw_mid();
            else if (test_name == "simul_rw_full")
                test_simul_rw_full();
            else if (test_name == "simul_rw_empty")
                test_simul_rw_empty();
            else if (test_name == "wraparound")
                test_wraparound();
            else if (test_name == "random_balanced")
                run_random(10000, 50, 50);
            else if (test_name == "random_write_heavy")
                run_random(10000, 75, 25);
            else if (test_name == "random_read_heavy")
                run_random(10000, 25, 75);
            else if (test_name == "reset_mid_traffic")
                test_reset_mid_traffic();
            else begin
                $display("ERROR: unknown test '%s'", test_name);
                errors = errors + 1;
            end
            settle();
        end
    endtask

    task automatic print_coverage;
        begin
            $display("COVERAGE occupancy: empty=%0d one=%0d middle=%0d almost_full=%0d full=%0d",
                     empty_bin, one_bin, middle_bin, almost_full_bin, full_bin);
            $display("COVERAGE events: write_full=%0d read_empty=%0d simultaneous_empty=%0d simultaneous_middle=%0d simultaneous_full=%0d",
                     write_while_full, read_while_empty, simultaneous_empty,
                     simultaneous_middle, simultaneous_full);
            $display("COVERAGE wraps: writes=%0d reads=%0d", write_wraps, read_wraps);
            if (single_test) begin
                $display("COVERAGE CHECK SKIPPED: selected test does not run the full suite");
            end else begin
                if (empty_bin == 0) $display("COVERAGE HOLE: occupancy_empty");
                if (one_bin == 0) $display("COVERAGE HOLE: occupancy_one");
                if ((DEPTH > 3) && (middle_bin == 0))
                    $display("COVERAGE HOLE: occupancy_middle");
                if (almost_full_bin == 0)
                    $display("COVERAGE HOLE: occupancy_almost_full");
                if (full_bin == 0) $display("COVERAGE HOLE: occupancy_full");
                if (write_while_full == 0)
                    $display("COVERAGE HOLE: write_requested_full");
                if (read_while_empty == 0)
                    $display("COVERAGE HOLE: read_requested_empty");
                if (simultaneous_empty == 0)
                    $display("COVERAGE HOLE: simultaneous_empty");
                if (simultaneous_middle == 0)
                    $display("COVERAGE HOLE: simultaneous_middle");
                if (simultaneous_full == 0)
                    $display("COVERAGE HOLE: simultaneous_full");
                if (write_wraps < 2) $display("COVERAGE HOLE: write_wraparound");
                if (read_wraps < 2) $display("COVERAGE HOLE: read_wraparound");
            end
        end
    endtask

    initial begin
        fifo_if.rstn = 1'b0;
        fifo_if.w_en = 1'b0;
        fifo_if.r_en = 1'b0;
        fifo_if.data_in = '0;
        if ($value$plusargs("seed=%d", seed_value) == 0)
            seed_value = 1;
        if ($value$plusargs("test=%s", selected_test) == 0)
            selected_test = "all";
        random_seed = seed_value;
        random_value = $urandom(random_seed);
        single_test = (selected_test != "all");

        $display("sync_fifo testbench: DEPTH=%0d DATAW=%0d seed=%0d test=%s",
                 DEPTH, DATAW, seed_value, selected_test);
        if ((DEPTH < 2) || (DATAW < 1)) begin
            $display("ERROR: DEPTH must be >= 2 and DATAW must be >= 1");
            $fatal(1);
        end

        if (single_test) begin
            run_named_test(selected_test);
        end else begin
            run_named_test("reset");
            run_named_test("fill_to_full");
            run_named_test("drain_to_empty");
            run_named_test("overflow_attempt");
            run_named_test("underflow_attempt");
            run_named_test("simul_rw_mid");
            run_named_test("simul_rw_full");
            run_named_test("simul_rw_empty");
            run_named_test("wraparound");
            run_named_test("random_balanced");
            run_named_test("random_write_heavy");
            run_named_test("random_read_heavy");
            run_named_test("reset_mid_traffic");
        end

        print_coverage();
        if (errors == 0) begin
            $display("TEST PASSED (%0d writes, %0d reads, 0 errors, seed=%0d)",
                     accepted_writes, accepted_reads, seed_value);
            $finish;
        end else begin
            $display("TEST FAILED (%0d writes, %0d reads, %0d errors, seed=%0d)",
                     accepted_writes, accepted_reads, errors, seed_value);
            $fatal(1);
        end
    end
endmodule
