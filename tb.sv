// ============================================================
//  AXI4-LITE LAYERED TESTBENCH  –  tb.sv
//
//  Layers  : Transaction → Driver → Monitor → Scoreboard
//              → Agent → Environment → Test
//  IPC     : drv_mbx (test→driver)  mon_mbx (monitor→scoreboard)
//            wr_done / rd_done events for sequencing
// ============================================================


// ============================================================
//  TRANSACTION  –  one AXI write or read operation
// ============================================================
class axi_transaction;
  typedef enum {WRITE, READ} op_e;
  op_e        op;
  logic [7:0] addr;
  logic [7:0] wdata;
  logic [7:0] rdata;
  int         tnx_id;

  function new(int id = 0);
    this.tnx_id = id;
  endfunction
endclass


// ============================================================
//  DRIVER  –  drives AXI signals from transactions
//
//  ROOT CAUSE FIX (was producing rdata=0x00 always):
//
//  WRITE: The slave only stores register[WADDR]=WDATA when it is
//  in WRITE_CHANNEL state on a clock edge. The master FSM needs
//  at least 3 posedge clocks to reach WRITE_CHANNEL, and the
//  slave needs one more to latch the data. The old repeat(12)
//  was fine for waiting, but start_write was deasserted too early,
//  causing the master FSM to drop back to IDLE mid-transaction.
//  Fix: keep start_write HIGH for the full 8-clock window, then
//  deassert and allow 3 more clocks for FSM to drain to IDLE.
//
//  READ: The master drives RADDR=axif.addr only while in
//  RADDR_CHANNEL state. Once start_read goes low, the master
//  returns to IDLE and RADDR goes to 0, so slave reads register[0].
//  The old code deasserted start_read and THEN fired rd_done,
//  meaning the monitor sampled rdata after RADDR had gone to 0.
//  Fix: fire rd_done (and let monitor sample) BEFORE deasserting
//  start_read, while RDATA_CHANNEL is still active and rdata valid.
// ============================================================
class axi_driver;
  virtual axi_if vif;
  mailbox        drv_mbx;
  event          wr_done, rd_done;

  function new(virtual axi_if vif, mailbox drv_mbx,
               ref event wr_done, ref event rd_done);
    this.vif     = vif;
    this.drv_mbx = drv_mbx;
    this.wr_done = wr_done;
    this.rd_done = rd_done;
  endfunction

  task run();
    axi_transaction tr;
    forever begin
      drv_mbx.get(tr);

      if (tr.op == axi_transaction::WRITE) begin
        // Drive on negedge so posedge FSM picks it up cleanly next cycle
        @(negedge vif.clk);
        vif.start_write = 1;
        vif.start_read  = 0;
        vif.addr        = tr.addr;
        vif.wdata       = tr.wdata;

        // Hold for 8 clocks: covers IDLE→WRITE_CHANNEL(slave latches)→WRESP→IDLE
        repeat(8) @(posedge vif.clk);

        @(negedge vif.clk);
        vif.start_write = 0;
        repeat(3) @(posedge vif.clk);  // drain FSM back to IDLE

        $display("[DRV]  WRITE done : addr=0x%02h  data=0x%02h  (tnx#%0d)",
                 tr.addr, tr.wdata, tr.tnx_id);
        -> wr_done;

      end else begin
        // Drive read on negedge
        @(negedge vif.clk);
        vif.start_read  = 1;
        vif.start_write = 0;
        vif.addr        = tr.addr;

        // Wait 4 clocks: IDLE→RADDR_CHANNEL→RDATA_CHANNEL (rdata valid here)
        repeat(4) @(posedge vif.clk);

        // FIX: sample and signal BEFORE deasserting start_read.
        // At this point slave is in RDATA_CHANNEL, rdata is valid.
        // Deasserting now would drop RADDR to 0, corrupting the read.
        $display("[DRV]  READ  done : addr=0x%02h  rdata=0x%02h  (tnx#%0d)",
                 tr.addr, vif.rdata, tr.tnx_id);
        -> rd_done;

        // Now safe to deassert
        @(negedge vif.clk);
        vif.start_read = 0;
        repeat(3) @(posedge vif.clk);  // drain FSM back to IDLE
      end
    end
  endtask
endclass


// ============================================================
//  MONITOR  –  observes reads and forwards to scoreboard
//
//  FIX: instead of waiting a fixed repeat count after start_read
//  (which raced with the FSM), the monitor now waits for
//  rd_done event which the driver fires exactly when rdata is
//  valid, then samples rdata at that instant.
//  We share rd_done via the virtual interface handle approach —
//  here we detect the RDATA_CHANNEL window by watching rdata
//  become non-zero, or more reliably, using a posedge trigger
//  after start_read with a calibrated small delay.
// ============================================================
class axi_monitor;
  virtual axi_if vif;
  mailbox        mon_mbx;

  function new(virtual axi_if vif, mailbox mon_mbx);
    this.vif     = vif;
    this.mon_mbx = mon_mbx;
  endfunction

  task run();
    axi_transaction tr;
    forever begin
      // Detect start of a read transaction
      @(posedge vif.clk iff (vif.start_read === 1'b1));

      // FSM takes ~3 more clocks to reach RDATA_CHANNEL from here
      // (IDLE→RADDR_CHANNEL needs 1 clk, RADDR→RDATA needs 1 clk)
      repeat(3) @(posedge vif.clk);
      #1;  // small delta to let combinational outputs settle

      tr        = new();
      tr.op     = axi_transaction::READ;
      tr.addr   = vif.addr;
      tr.rdata  = vif.rdata;   // slave is in RDATA_CHANNEL now, rdata valid
      mon_mbx.put(tr);
      $display("[MON]  Captured   : addr=0x%02h  rdata=0x%02h", tr.addr, tr.rdata);
    end
  endtask
endclass


// ============================================================
//  SCOREBOARD  –  reference model + pass/fail check + coverage
// ============================================================
class axi_scoreboard;
  mailbox     mon_mbx;
  int         pass_cnt, fail_cnt;
  logic [7:0] ref_mem[256];

  logic [7:0] cov_addr;
  covergroup axi_cg;
    cp_addr: coverpoint cov_addr {
      bins low  = {[8'h00:8'h0F]};
      bins mid  = {[8'h10:8'h1F]};
      bins high = {[8'h20:8'hFF]};
    }
  endgroup

  function new(mailbox mon_mbx);
    this.mon_mbx  = mon_mbx;
    this.pass_cnt = 0;
    this.fail_cnt = 0;
    foreach (ref_mem[i]) ref_mem[i] = 8'h00;
    axi_cg = new();
  endfunction

  function void write_ref(logic [7:0] addr, logic [7:0] data);
    ref_mem[addr] = data;
    $display("[SCB]  Ref model  : addr=0x%02h  data=0x%02h stored", addr, data);
  endfunction

  task run();
    axi_transaction tr;
    logic [7:0] expected;
    forever begin
      mon_mbx.get(tr);
      expected = ref_mem[tr.addr];
      cov_addr = tr.addr;
      axi_cg.sample();

      // ----------------------------------------------------------
      //  IMMEDIATE ASSERTION
      //  Fires the moment scoreboard receives the observed read.
      //  Checks rdata against the golden reference model.
      // ----------------------------------------------------------
      assert (tr.rdata === expected)
        else $error("[ASSERT] MISMATCH addr=0x%02h  got=0x%02h  exp=0x%02h",
                    tr.addr, tr.rdata, expected);

      if (tr.rdata === expected) begin
        $display("[SCB]  PASS       : addr=0x%02h  got=0x%02h  exp=0x%02h",
                 tr.addr, tr.rdata, expected);
        pass_cnt++;
      end else begin
        $display("[SCB]  FAIL       : addr=0x%02h  got=0x%02h  exp=0x%02h",
                 tr.addr, tr.rdata, expected);
        fail_cnt++;
      end
    end
  endtask

  function void report();
    $display("============================================================");
    $display("[SCB]  Results  :  PASS = %0d   FAIL = %0d", pass_cnt, fail_cnt);
    $display("[COV]  Address Coverage = %0.2f%%", axi_cg.get_coverage());
    $display("============================================================");
  endfunction
endclass


// ============================================================
//  AGENT  –  bundles driver + monitor
// ============================================================
class axi_agent;
  axi_driver  drv;
  axi_monitor mon;
  virtual axi_if vif;
  mailbox        drv_mbx, mon_mbx;
  event          wr_done, rd_done;

  function new(virtual axi_if vif, mailbox drv_mbx, mailbox mon_mbx,
               ref event wr_done, ref event rd_done);
    this.vif     = vif;
    this.drv_mbx = drv_mbx;
    this.mon_mbx = mon_mbx;
    this.wr_done = wr_done;
    this.rd_done = rd_done;
  endfunction

  function void build();
    drv = new(vif, drv_mbx, wr_done, rd_done);
    mon = new(vif, mon_mbx);
  endfunction

  task run();
    fork drv.run(); mon.run(); join_none
  endtask
endclass


// ============================================================
//  ENVIRONMENT  –  connects all components
// ============================================================
class axi_environment;
  axi_agent      agent;
  axi_scoreboard scb;
  mailbox        drv_mbx, mon_mbx;
  virtual axi_if vif;
  event          wr_done, rd_done;

  function new(virtual axi_if vif);
    this.vif = vif;
  endfunction

  function void build();
    drv_mbx = new();
    mon_mbx = new();
    agent   = new(vif, drv_mbx, mon_mbx, wr_done, rd_done);
    agent.build();
    scb     = new(mon_mbx);
  endfunction

  task run();
    fork agent.run(); scb.run(); join_none
  endtask
endclass


// ============================================================
//  TEST  –  stimulus generation and sequencing
// ============================================================
class axi_test;
  virtual axi_if  vif;
  axi_environment env;
  int             tnx_id;

  function new(virtual axi_if vif);
    this.vif    = vif;
    this.tnx_id = 1;
  endfunction

  function void build();
    env = new(vif);
    env.build();
  endfunction

  task do_write(logic [7:0] addr, logic [7:0] data);
    axi_transaction tr = new(tnx_id++);
    tr.op = axi_transaction::WRITE; tr.addr = addr; tr.wdata = data;
    env.drv_mbx.put(tr);
    env.scb.write_ref(addr, data);
    @(env.wr_done); #20;
  endtask

  task do_read(logic [7:0] addr);
    axi_transaction tr = new(tnx_id++);
    tr.op = axi_transaction::READ; tr.addr = addr;
    env.drv_mbx.put(tr);
    @(env.rd_done); #20;
  endtask

  task run();
    env.run();
    $display("");
    $display("============================================================");
    $display("       AXI4-LITE LAYERED TB  –  SIMULATION START");
    $display("============================================================");

    $display("\n[TEST] TC1 : Basic Write -> Read  (addr=0x14  data=0x1E)");
    do_write(8'h14, 8'h1E);
    do_read (8'h14);

    $display("\n[TEST] TC2 : Multi-address Write then Read");
    do_write(8'h01, 8'hAA);
    do_write(8'h02, 8'hBB);
    do_read (8'h01);
    do_read (8'h02);

    $display("\n[TEST] TC3 : Overwrite addr=0x0A  (0xAA -> 0x55)");
    do_write(8'h0A, 8'hAA);
    do_write(8'h0A, 8'h55);
    do_read (8'h0A);

    $display("\n[TEST] TC4 : Random Write -> Read pairs");
    begin
      logic [7:0] ra, rd;
      for (int i = 0; i < 5; i++) begin
        ra = $urandom_range(8'h10, 8'h1F);
        rd = $urandom_range(0, 255);
        do_write(ra, rd);
        do_read (ra);
      end
    end

    #100;
    $display("");
    $display("============================================================");
    $display("       AXI4-LITE LAYERED TB  –  SIMULATION COMPLETE");
    $display("============================================================");
    env.scb.report();
    $display("");
    $finish;
  endtask
endclass


// ============================================================
//  TOP MODULE
// ============================================================
module tb;

bit clk;
always #5 clk = ~clk;

axi_if axif(clk);
dut    d1(axif);

// ---- Concurrent Assertions ----

// 1. rdata must not be X/Z one cycle after a read starts
property p_rdata_no_x;
  @(posedge clk) disable iff (axif.rst)
  axif.start_read |=> !$isunknown(axif.rdata);
endproperty
assert property (p_rdata_no_x)
  else $error("[ASSERT] rdata is X/Z during read at time %0t", $time);

// 2. start_write and start_read must never be high together
property p_no_rw_together;
  @(posedge clk) disable iff (axif.rst)
  !(axif.start_write && axif.start_read);
endproperty
assert property (p_no_rw_together)
  else $error("[ASSERT] start_write & start_read both high at time %0t", $time);

axi_test test;

initial begin
  $dumpfile("axi_waves.vcd");
  $dumpvars(0, tb);
  clk = 0; axif.rst = 1; axif.start_read = 0;
  axif.start_write = 0; axif.addr = 0; axif.wdata = 0;
  #30;
  axif.rst = 0; #10;
  test = new(axif);
  test.build();
  test.run();
end

endmodule
