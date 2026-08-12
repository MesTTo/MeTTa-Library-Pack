;Purpose: PyTorch from plain MeTTa through py-call, no Python-side setup
;  needed beyond torch being importable. The pettorch Python package registers
;  a richer operation set (identity-preserving tensors, modules as functions,
;  knn); this library is the CLI-reachable half, in the shape examples/torch.metta
;  established.
;Open Obligations:
;  To Do: None
;  Hacks: None
;  Future Enhancements: None
;
;Usage: !(import! &self (library lib_torch))

;Construction:
(= (torch-tensor $data) (py-call (torch.tensor $data)))
(= (torch-zeros $n) (py-call (torch.zeros $n)))
(= (torch-ones $n) (py-call (torch.ones $n)))
(= (torch-randn $n) (py-call (torch.randn $n)))
(= (torch-arange $n) (py-call (torch.arange $n)))

;Algebra:
(= (torch-matmul $a $b) (py-call (torch.matmul $a $b)))
(= (torch-add $a $b) (py-call (torch.add $a $b)))
(= (torch-sub $a $b) (py-call (torch.sub $a $b)))
(= (torch-mul $a $b) (py-call (torch.mul $a $b)))
(= (torch-div $a $b) (py-call (torch.div $a $b)))

;Reductions and activations:
(= (torch-sum $a) (py-call (torch.sum $a)))
(= (torch-mean $a) (py-call (torch.mean $a)))
(= (torch-relu $a) (py-call (torch.relu $a)))
(= (torch-sigmoid $a) (py-call (torch.sigmoid $a)))

;Exits back to MeTTa data:
(= (torch-item $a) (py-call (.item $a)))
(= (torch-tolist $a) (py-call (.tolist $a)))
(= (torch-shape $a) (py-call (list (py-call (getattr $a shape)))))

;Autograd:
;requires_grad_ defaults to True; py-call would pass the boolean atom as the
;string "true", so the argument-free form is the correct spelling here.
(= (torch-requires-grad $a) (py-call (.requires_grad_ $a)))
(= (torch-backward $a) (py-call (.backward $a)))
(= (torch-grad $a) (py-call (getattr $a grad)))
