// One step of the ten-class argmax scan used by the top-level controller.
module argmax_step_int8 (
    input wire signed [31:0] score,
    input wire signed [31:0] best_score,
    output wire update_best
);
    assign update_best = (score > best_score);
endmodule
