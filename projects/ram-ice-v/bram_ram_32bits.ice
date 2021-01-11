// SL 2020-12-22 @sylefeb
//
// ------------------------- 

$$ bram_depth = 12
$$ bram_size  = 1<<bram_depth

algorithm bram_ram_32bits(
  rv32i_ram_provider pram,       // provided ram interface
  input uint26 predicted_addr,         // next predicted address
) <autorun> {

  simple_dualport_bram uint32 mem[$bram_size$] = { $data_bram$ pad(uninitialized) };
  
  uint1 in_scope      := (pram.addr[29,3] == 3b00); // Note: memory mapped addresses use the top most bits
  uint1 pred_correct ::= (mem.addr0 == pram.addr[2,$bram_depth$]);
  uint1 wait_one(0);
  
  uint24 pred_reg = uninitialized;

$$if verbose then                          
  uint20 cycle = 0;
$$end  
  
  while (1) {
$$if verbose then  
    if (pram.in_valid | wait_one) {
      __display("[cycle%d] in_valid:%b wait:%b addr_in:%h rw:%b prev:@%h predok:%b newpred:@%h",cycle,pram.in_valid,wait_one,pram.addr[2,24],pram.rw,mem.addr0,pred_correct,predicted_addr[2,$bram_depth$]);  
    }
$$end
    pram.data_out       = mem.rdata0 >> {pram.addr[0,2],3b000};    
    pram.done           = ((pred_correct & pram.in_valid) | wait_one);
    mem.addr0           = (~pred_correct & (pram.in_valid | wait_one))
                          ? pram.addr[2,$bram_depth$] : pred_reg[0,$bram_depth$]; // predict
    pred_reg            = predicted_addr[2,$bram_depth$];
    mem.addr1           = pram.addr[2,$bram_depth$];
    mem.wenable1        = pram.rw & ((pred_correct & pram.in_valid) | wait_one) & in_scope;
    mem.wdata1          = {
                            pram.wmask[3,1] ? pram.data_in[24,8] : mem.rdata0[24,8],
                            pram.wmask[2,1] ? pram.data_in[16,8] : mem.rdata0[16,8],
                            pram.wmask[1,1] ? pram.data_in[ 8,8] : mem.rdata0[ 8,8],
                            pram.wmask[0,1] ? pram.data_in[ 0,8] : mem.rdata0[ 0,8]
                          };   
$$if verbose then  
    if (pram.in_valid | wait_one) {                        
      __display("          done:%b wait:%b pred:@%h out:%h wen:%b",pram.done,wait_one,mem.addr0,pram.data_out,mem.wenable1);  
    }
    cycle = cycle + 1;
$$end    
    wait_one            = (pram.in_valid & ~pred_correct);
  }
}
