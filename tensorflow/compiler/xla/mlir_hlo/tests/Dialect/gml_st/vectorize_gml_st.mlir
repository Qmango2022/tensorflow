// RUN: mlir-hlo-opt %s --split-input-file \
// RUN:     --vectorize-gml-st-loops="vectorize-gml-st-ops=true included-distribution-labels=test" \
// RUN: | FileCheck %s

func.func @vectorize_gml_st_parallel_op(
    %arg0: tensor<32xf32>, %arg1: tensor<32xf32>)
    -> tensor<32xf32> {
  %c4 = arith.constant 4 : index
  %c1 = arith.constant 1 : index
  %c0 = arith.constant 0 : index
  %c32 = arith.constant 32 : index
  // We need this outer trivial loop to make sure the inner loop has a parent
  // with the correct distribution label.
  %2 = gml_st.parallel (%unused) = (%c0) to (%c1) step (%c1)
          distribution ("test") {
    %arg0tile = tensor.extract_slice %arg0[0][32][1]
      : tensor<32xf32> to tensor<32xf32>
    %arg1tile = tensor.extract_slice %arg1[0][32][1]
      : tensor<32xf32> to tensor<32xf32>
    %3 = gml_st.parallel (%i) = (%c0) to (%c32) step (%c4)
          distribution ("test") {
      %6 = tensor.extract_slice %arg0tile[%i] [4] [1]
        : tensor<32xf32> to tensor<4xf32>
      %7 = tensor.extract_slice %arg1tile[%i] [4] [1]
        : tensor<32xf32> to tensor<4xf32>
      %9 = linalg.map {arith.negf }
             ins(%6: tensor<4xf32>)
             outs(%7 : tensor<4xf32>)
      %tile = gml_st.tile [%i] [4] [1] : !gml_st.tile<4>
      gml_st.set_yield %9 into %arg1tile[%tile]
        : tensor<4xf32> into tensor<32xf32>[!gml_st.tile<4>]
    } : tensor<32xf32>
    %tile32 = gml_st.tile [0][32][1] : !gml_st.tile<32>
    gml_st.set_yield %3 into %arg1[%tile32]
      : tensor<32xf32> into tensor<32xf32>[!gml_st.tile<32>]
  } : tensor<32xf32>
  func.return %2 : tensor<32xf32>
}
// CHECK-LABEL: @vectorize_gml_st_parallel_op(
// CHECK-SAME:   %[[ARG0:.*]]: tensor<32xf32>, %[[ARG1:.*]]: tensor<32xf32>

// CHECK:      %[[C0:.*]] = arith.constant 0 : index
// CHECK:      gml_st.parallel
// CHECK-DAG:    vector.transfer_read %[[ARG1]][%[[C0]]]
// CHECK:        %[[RESULT:.*]] = gml_st.parallel
// CHECK:          %[[LHSTILE:.*]] = tensor.extract_slice %[[ARG0]]
// CHECK:          %[[LHSVEC:.*]] = vector.transfer_read %[[LHSTILE]]
// CHECK:          %[[NEG:.*]] = arith.negf %[[LHSVEC]] : vector<4xf32>
// CHECK:          gml_st.set_yield %[[NEG]]
// CHECK-SAME:     vector<4xf32> into vector<32xf32>
// CHECK:        vector.transfer_write %[[RESULT]], {{%.*}}[%c0]

// -----

func.func @vectorize_gml_st_for_op(
    %arg0: tensor<32xf32>, %arg1: tensor<32xf32>)
    -> tensor<32xf32> {
  %c4 = arith.constant 4 : index
  %c1 = arith.constant 1 : index
  %c0 = arith.constant 0 : index
  %c32 = arith.constant 32 : index
  // We need this outer trivial loop to make sure the inner loop has a parent
  // with the correct distribution label.
  %2 = gml_st.parallel (%unused) = (%c0) to (%c1) step (%c1)
          distribution ("test") {
    %arg0tile = tensor.extract_slice %arg0[0][32][1]
      : tensor<32xf32> to tensor<32xf32>
    %arg1tile = tensor.extract_slice %arg1[0][32][1]
      : tensor<32xf32> to tensor<32xf32>
    %3 = gml_st.for (%i) = (%c0) to (%c32) step (%c4)
          outs(%out = %arg1tile : tensor<32xf32>) {
      %6 = tensor.extract_slice %arg0tile[%i][4][1]
        : tensor<32xf32> to tensor<4xf32>
      %7 = tensor.extract_slice %out[%i][4][1]
        : tensor<32xf32> to tensor<4xf32>
      %9 = linalg.map { arith.negf }
              ins(%6: tensor<4xf32>)
              outs(%7 : tensor<4xf32>)
      %tile = gml_st.tile [%i] [4] [1] : !gml_st.tile<4>
      gml_st.set_yield %9 into %out[%tile]
        : tensor<4xf32> into tensor<32xf32>[!gml_st.tile<4>]
    } : tensor<32xf32>
    %tile32 = gml_st.tile [0][32][1] : !gml_st.tile<32>
    gml_st.set_yield %3 into %arg1[%tile32]
      : tensor<32xf32> into tensor<32xf32>[!gml_st.tile<32>]
  } : tensor<32xf32>
  func.return %2 : tensor<32xf32>
}
// CHECK-LABEL: @vectorize_gml_st_for_op(
// CHECK-SAME:   %[[ARG0:.*]]: tensor<32xf32>, %[[ARG1:.*]]: tensor<32xf32>

// CHECK:      %[[C0:.*]] = arith.constant 0 : index
// CHECK:      gml_st.parallel
// CHECK-DAG:  %[[RES:.*]] = vector.transfer_read %[[ARG1]][%[[C0]]]
// CHECK:      %[[RESULT:.*]] = gml_st.for
// CHECK-SAME:     outs (%[[OUT:.*]] = %[[RES]]: vector<32xf32>)
// CHECK-DAG:    %[[LHSTILE:.*]] = tensor.extract_slice %[[ARG0]]
// CHECK-DAG:    %[[LHSVEC:.*]] = vector.transfer_read %[[LHSTILE]]
// CHECK:        %[[NEG:.*]] = arith.negf %[[LHSVEC]] : vector<4xf32>
// CHECK:        gml_st.set_yield %[[NEG]] into %[[OUT]]
// CHECK-SAME:   vector<4xf32> into vector<32xf32>

// -----

func.func @vectorize_loop_on_scalars(
    %arg0: tensor<32xf32>, %arg1: tensor<32xf32>) -> tensor<32xf32> {
  %c4 = arith.constant 4 : index
  %c1 = arith.constant 1 : index
  %c0 = arith.constant 0 : index
  %c32 = arith.constant 32 : index
  // We need this outer trivial loop to make sure the inner loop has a parent
  // with the correct distribution label.
  %2 = gml_st.parallel (%unused) = (%c0) to (%c1) step (%c1)
          distribution ("test") {
    %arg0tile = tensor.extract_slice %arg0[0][32][1]
      : tensor<32xf32> to tensor<32xf32>
    %arg1tile = tensor.extract_slice %arg1[0][32][1]
      : tensor<32xf32> to tensor<32xf32>
    %3 = gml_st.for (%i) = (%c0) to (%c32) step (%c4)
          outs(%out = %arg1tile : tensor<32xf32>) {
      %6 = tensor.extract_slice %arg0tile[%i][1][1]
        : tensor<32xf32> to tensor<1xf32>
      %7 = tensor.extract %6[%c0] : tensor<1xf32>
      %9 = arith.negf %7 : f32
      %tile = gml_st.tile [%i] [1] [1] : !gml_st.tile<1>
      gml_st.set_yield %9 into %out[%tile]
        : f32 into tensor<32xf32>[!gml_st.tile<1>]
    } : tensor<32xf32>
    %tile32 = gml_st.tile [0][32][1] : !gml_st.tile<32>
    gml_st.set_yield %3 into %arg1[%tile32]
      : tensor<32xf32> into tensor<32xf32>[!gml_st.tile<32>]
  } : tensor<32xf32>
  func.return %2 : tensor<32xf32>
}
// CHECK-LABEL: @vectorize_loop_on_scalars(
// CHECK-SAME:   %[[ARG0:.*]]: tensor<32xf32>, %[[ARG1:.*]]: tensor<32xf32>

// CHECK:      %[[C0:.*]] = arith.constant 0 : index
// CHECK:      gml_st.parallel
// CHECK-DAG:  %[[RES:.*]] = vector.transfer_read %[[ARG1]][%[[C0]]]
// CHECK:      %[[RESULT:.*]] = gml_st.for
// CHECK-SAME:     outs (%[[OUT:.*]] = %[[RES]]: vector<32xf32>)
// CHECK:        %[[LHSTILE:.*]] = tensor.extract_slice %[[ARG0]]
// CHECK:        %[[LHSVEC:.*]] = vector.transfer_read %[[LHSTILE]][%c0]
// CHECK:        %[[LHSELEM:.*]] = vector.extract %[[LHSVEC]]
// CHECK:        %[[NEG:.*]] = arith.negf %[[LHSELEM]] : f32
// CHECK:        gml_st.set_yield %[[NEG]] into %[[OUT]]
// CHECK-SAME:   f32 into vector<32xf32>

// -----

// CHECK-LABEL: @skip_vectorization_with_wrong_label(
func.func @skip_vectorization_with_wrong_label(
    %arg0: tensor<32xf32>, %arg1: tensor<32xf32>)
    -> tensor<32xf32> {
  %c4 = arith.constant 4 : index
  %c1 = arith.constant 1 : index
  %c0 = arith.constant 0 : index
  %c32 = arith.constant 32 : index
  %2 = gml_st.parallel (%unused) = (%c0) to (%c1) step (%c1)
          distribution ("no_vec") {
    %3 = gml_st.parallel (%i) = (%c0) to (%c32) step (%c4)
            distribution ("no_vec") {
      %6 = tensor.extract_slice %arg0[%i][4][1]
        : tensor<32xf32> to tensor<4xf32>
      %7 = tensor.extract_slice %arg1[%i][4][1]
        : tensor<32xf32> to tensor<4xf32>
      %9 = linalg.map { arith.negf }
             ins(%6: tensor<4xf32>)
             outs(%7 : tensor<4xf32>)
      %tile = gml_st.tile [%i] [4] [1] : !gml_st.tile<4>
      gml_st.set_yield %9 into %arg1[%tile]
        : tensor<4xf32> into tensor<32xf32>[!gml_st.tile<4>]
    } : tensor<32xf32>
    %tile32 = gml_st.tile [0][32][1] : !gml_st.tile<32>
    gml_st.set_yield %3 into %arg1[%tile32]
      : tensor<32xf32> into tensor<32xf32>[!gml_st.tile<32>]
  } : tensor<32xf32>
  func.return %2 : tensor<32xf32>
}
// CHECK-NOT: vector.transfer_read

// -----

// CHECK-LABEL: @materialize_to_scalar(
func.func @materialize_to_scalar(%arg1 : tensor<4xf32>) -> tensor<4xf32> {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %empty = tensor.empty() : tensor<4xf32>
  %1 = gml_st.parallel (%arg2) = (%c0) to (%c1) step (%c1)
            distribution ("test") {
    %5 = tensor.extract_slice %arg1[1][4][1]
      : tensor<4xf32> to tensor<4xf32>
    %3 = tensor.extract_slice %5[1][1][1]
      : tensor<4xf32> to tensor<1xf32>
    %4 = tensor.extract %3[%c0] : tensor<1xf32>
    // CHECK: gml_st.materialize {{.*}} : vector<4xf32> to f32
    %2 = arith.negf %4 : f32
    %point = gml_st.tile [1][1][1] : !gml_st.tile<1>
    gml_st.set_yield %2 into %empty[%point]
      : f32 into tensor<4xf32>[!gml_st.tile<1>]
  } : tensor<4xf32>
  return %1 : tensor<4xf32>
}

// -----

// CHECK-LABEL: @materialize_to_dynamic_tile(
func.func @materialize_to_dynamic_tile(%arg1 : tensor<4xf32>, %size : index)
    -> tensor<4xf32> {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %empty = tensor.empty() : tensor<4xf32>
  %0 = gml_st.parallel (%arg3) = (%c0) to (%c1) step (%c1)
            distribution ("test") {
    %1 = gml_st.parallel (%arg2) = (%c0) to (%c1) step (%c1)
              distribution ("test") {
      %2 = tensor.extract_slice %arg1[1][4][1]
        : tensor<4xf32> to tensor<4xf32>
      %3 = tensor.extract_slice %2[1][%size][1]
        : tensor<4xf32> to tensor<?xf32>
      %dynTile = gml_st.tile [1][%size][1] : !gml_st.tile<?>
      gml_st.set_yield %3 into %empty[%dynTile]
        : tensor<?xf32> into tensor<4xf32>[!gml_st.tile<?>]
    } : tensor<4xf32>
    %tile = gml_st.tile [1][4][1] : !gml_st.tile<4>
    gml_st.set_yield %1 into %empty[%tile]
      : tensor<4xf32> into tensor<4xf32>[!gml_st.tile<4>]
  } : tensor<4xf32>
  return %0 : tensor<4xf32>
}
// CHECK-NOT: vector
