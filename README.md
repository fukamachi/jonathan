# Jonathan

## Usage

```
(in-package :cl-user)
(defpackage sample-app
  (:use :cl :jonathan))
  (in-package :sample-app)

  (syntax:use-syntax :annot)

  (set-app :sample-app)
  (start-routing-rules)

  @GETAPI
  (defun sample ()
    (list :key1  :value1))

; /api/sample => {"key1":"key2"}
```

## Install
- `(ql:quickload :jonathan)`
- `npm install --save react-jonathan`

## Author

* Rudolph-Miller

## Copyright

Copyright (c) 2015 Rudolph-Miller