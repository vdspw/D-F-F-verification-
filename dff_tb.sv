// Transaction
 class transaction;
   
   rand bit din; //randomization 
   bit dout;
   
   function transaction copy(); // deep copy of the objects
     copy = new();
     copy.din = this.din;
     copy.dout = this.dout;
   endfunction
   
   function void display(input string tag);
     $display("[%0s] : D-INPUT is : %0b and D-OUT is : %0b",tag, din,dout);
   endfunction
   
   
 endclass

//////////////////////////////////////////////////////////////////////////

// generator
class generator;
  transaction tr;
  mailbox #(transaction) mbx; // send data to the driver.
  mailbox #(transaction) mbxref; //send ref_data to the scoreboard.
  event sconext; //on completion of the scoreboard event.
  event done;	// on completion of sending required no. of stimulii.
  int count ; // count of stimulii.
  
  function new(mailbox #(transaction) mbx , mailbox #(transaction) mbxref);
    this.mbx = mbx;
    this.mbxref = mbxref;
    tr = new();
  endfunction
  
  task run();
    repeat(count)begin
      assert(tr.randomize) else $error("[GEN]: Randomization failed");
      mbx.put(tr.copy); // sending to the driver.
      mbxref.put(tr.copy); // sending to the scoreboard.
      tr.display("GEN");
      @(sconext);
      
    end
    ->done;
  endtask
  
  
endclass

//////////////////////////////////////////////////////////////////////////////
// driver
class driver;
  transaction tr;
  mailbox #(transaction) mbx;
  virtual dff_if vif; //virtual interface.
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  task reset();
    vif.rst <= 1'b1; //assert reset signal
    repeat(5) @(posedge vif.clk); //wit for 5 clk cycles
    vif.rst <= 1'b0;	//deassert the rest signal
    @(posedge vif.clk);
    $display("[DRV] RESET DONE");
  endtask
  
  task run();
    forever begin
    mbx.get(tr); // gets data from the generator.
    vif.din <= tr.din;
    @(posedge vif.clk);
    tr.display("[DRV]");
    vif.din <= 1'b0; // removing the impulses.
    @(posedge vif.clk);
    end
  endtask
  
endclass
/////////////////////////////////////////////////////////////////////////

// monitor

class monitor;
  transaction tr;
  mailbox #(transaction) mbx; //sends data to scoreboard
  virtual dff_if vif;
  
  function new (mailbox #(transaction) mbx);
    this.mbx = mbx; // initialization of the mailbox
  endfunction
  
  task run();
    tr = new();
    forever begin 
      repeat(2) @(posedge vif.clk);
      tr.dout = vif.dout; //store the response in the transaction item.
      mbx.put(tr);
      tr.display("[MON]");
    end
  endtask
  
endclass
////////////////////////////////////////////////////////////////////////////

//scoreboard

class scoreboard;
  transaction tr;
  transaction trref;
  mailbox #(transaction) mbx;//recieves data from the driver.
  mailbox #(transaction) mbxref;//recieves data from the scoreboard.
  event sconext;
  
  function new (mailbox #(transaction)mbx, mailbox #(transaction) mbxref);
    this.mbx = mbx;
    this.mbxref = mbxref;
  endfunction
  
  task run();
    forever begin
      mbx.get(tr);  //recienving data from the monitor.
      mbxref.get(trref); // recieving data from the generator.
      tr.display("[SCO]");
      trref.display("[REF]");
      if(tr.dout == trref.din)
        $display("[SCO] : DATA MATCHED");
      else
        $display("[SCO] : DATA MISMATCH");
      $display("------------------------------");
      ->sconext;
    end
  endtask
endclass

///////////////////////////////////////////////////////////////////////////

//environment

class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  
  event next;
  mailbox #(transaction) gdmbx; // gen -> drv
  mailbox #(transaction) msmbx; // mon -> sco
  mailbox #(transaction) mbxref; // gen -> sco
  
  virtual dff_if vif;
  
  function new(virtual dff_if vif);
    gdmbx = new();
    mbxref = new();
    gen = new(gdmbx,mbxref);
    drv = new(gdmbx);
    
    msmbx = new();
    mon = new(msmbx);
    sco = new(msmbx,mbxref);
    
    this.vif = vif;
    drv.vif = this.vif;
    mon.vif = this.vif;
    
    gen.sconext = next;
    sco.sconext = next;
    
  endfunction
  
  task pre_test();
    drv.reset();
  endtask
  
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  
  task post_test();
    wait(gen.done.triggered);
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
endclass

/////////////////////////////////////////////////////////////
// testbench top

module tb;
  
  dff_if vif();
  dff dut(vif);
  
  initial begin
    vif.clk <=0;
  end
  
  always #10 vif.clk <= ~vif.clk;
  
  environment env;
  
  initial begin
    env = new(vif);
    env.gen.count = 30; // setting the generator count
    env.run();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
endmodule
