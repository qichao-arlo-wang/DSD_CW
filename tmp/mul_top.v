module mul_top 
  (
   input [31:0]  dataa,
   input [31:0]  datab,
   output [31:0]  result
   );
    
  wire [63:0] temp_result;
    
  mul mul
    ( 
      .dataa(dataa),
      .datab(datab),
      .result(temp_result)
      );
		
 assign result = temp_result[31:0];  // Select the 32 LSBs for the output
 
endmodule // mul_top 
