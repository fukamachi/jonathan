(in-package :cl-user)
(defpackage jonathan.util
  (:use :cl :cl-cookie.util)
  (:import-from :jonathan.config
                :*template-directory*)
  (:import-from :caveman2
                :*response*
                :defroute)
  (:import-from :clack.response
                :headers)
  (:import-from :cl-emb
                :*escape-type*
                :*case-sensitivity*
                :*function-package*
                :execute-emb)
  (:import-from :fast-io
                :fast-write-byte
                :make-output-buffer
                :finish-output-buffer)
  (:import-from :xsubseq
                :xsubseq
                :coerce-to-string)
  (:import-from :datafly
                :encode-json)
  (:export :render-json
           :to-json
           :parse
           :parse1))
(in-package :jonathan.util)

(syntax:use-syntax :annot)

(defun render-json (object)
  (setf (headers *response* :content-type) "application/json")
  (encode-json (convert-object object)))

(defun convert-object (object)
  (if (typep object 'CONS)
      (if (typep (car object) 'KEYWORD)
          (loop for (key value) on object by #'cddr
             nconcing (list key (convert-object value)))
          (coerce object 'simple-vector))
      object))

(defmacro define-method (method)
  (let ((name (intern (concatenate 'string (symbol-name method) "API"))))
    `(defmacro ,name (&body body)
       (let* ((function-form (if (= (length body) 1)
                                 (cdar body)
                                 body))
              (func-name (car function-form))
              (func-args (cadr function-form))
              (func-body (caddr function-form))
              (path-name (concatenate 'string "/api/" (string-downcase (symbol-name func-name)))))
         (unless (gethash *package* caveman2.app::*package-app-map*)
           (setf (gethash *package* caveman2.app::*package-app-map*)
                 (gethash (find-package :jonathan.web) caveman2.app::*package-app-map*)))
         `(defroute ,func-name (,path-name :method ,,method) (,@func-args) (render-json ,func-body))))))

@export
(define-method :GET)

@export
(define-method :POST)

@export
(define-method :PUT)

@export
(define-method :DELETE)

(defun my-plist-p (list)
  (typecase list
    (null t)
    (cons (loop for (key val next) on list by #'cddr
                if (not (keywordp key))
                  return nil
                else
                  unless next return t))))

(declaim (optimize (speed 3) (safety 0) (debug 0)))

(defvar *to-json-octet-default* nil)
(defvar *stream* nil)
(defvar *octet* nil)

(declaim (inline %write-string))
(defun %write-string (string)
  (if *octet*
      (loop for c across string
            do (fast-write-byte (char-code c) *stream*))
      (write-string string *stream*)))

(declaim (inline %write-char))
(defun %write-char (char)
  (if *octet*
      (fast-write-byte (char-code char) *stream*)
      (write-char char *stream*)))

(defun to-json (obj &key (octet *to-json-octet-default*))
  "Converting object to JSON String."
  (let ((*stream* (if octet (make-output-buffer)
                      (make-string-output-stream)))
        (*octet* octet))
    (%to-json obj)
    (if octet
        (finish-output-buffer *stream*)
        (get-output-stream-string *stream*))))

(defgeneric %to-json (obj))

(defmethod %to-json ((string string))
  (%write-char #\")
  (loop for char across string
        do (case char
             (#\newline (%write-string "\\n"))
             (#\return (%write-string "\\r"))
             (#\tab (%write-string "\\t"))
             (#\" (%write-string "\\\""))
             (#\\ (%write-string "\\\\"))
             (t (%write-char char))))
  (%write-char #\"))

(defmethod %to-json ((number number))
  (%write-string (princ-to-string number)))

(defmethod %to-json ((ratio ratio))
  (%to-json (coerce ratio 'float)))

(defmethod %to-json ((list list))
  (if (my-plist-p list)
      (progn (%write-char #\{)
             (loop for (key val next) on list by #'cddr
                   do (%to-json (princ-to-string key))
                   do (%write-char #\:)
                   do (%to-json val)
                   when next do (%write-char #\,))
             (%write-char #\}))
      (progn (%write-char #\[)
             (loop for (item next) on list
                   do (%to-json item)
                   when next do (%write-char #\,))
             (%write-char #\]))))

(defmethod %to-json ((symbol symbol))
  (%to-json (symbol-name symbol)))

(defmethod %to-json ((true (eql t)))
  (declare (ignore true))
  (%write-string "true"))

(defmethod %to-json ((false (eql :false)))
  (declare (ignore false))
  (%write-string "false"))

(defmethod %to-json ((false (eql :null)))
  (declare (ignore false))
  (%write-string "null"))

(defmethod %to-json ((n (eql nil)))
  (declare (ignore n))
  (%write-string "[]"))

(defstruct (buffer (:constructor %make-buffer))
  (string "" :type string)
  (current 0 :type fixnum)
  (max 0 :type fixnum))

(defun make-buffer (string)
  (%make-buffer :string string :max (length string)))

(declaim (inline buffer-current-char))
(defun buffer-current-char (buffer)
  (char (buffer-string buffer)
        (buffer-current buffer)))

(declaim (inline buffer-current-char-eql))
(defun buffer-current-char-eql (buffer ch)
  (eql (buffer-current-char buffer) ch))

(declaim (inline buffer-elt))
(defun buffer-elt (buffer num)
  (char (buffer-string buffer) num))

(declaim (inline buffer-subseq))
(defun buffer-subseq (buffer start end)
  (coerce-to-string
   (xsubseq (buffer-string buffer) start end)))

(defun parse (string)
  (declare (type string string))
  (let ((buf (make-buffer string)))
    (%read buf)))

(defmacro %skip-to (form)
  `(do ((ch (buffer-current-char buffer) (buffer-current-char buffer)))
       (,form
        (1- (buffer-current buffer)))
     (if (eql ch #\\)
         (incf (buffer-current buffer) 2)
         (incf (buffer-current buffer)))))

(declaim (inline skip-to*))
(defun skip-to* (buffer string)
  (declare (type buffer buffer)
           (type string string))
  (%skip-to (find ch string)))

(declaim (inline skip-to))
(defun skip-to (buffer char)
  (declare (type buffer buffer)
           (type standard-char char))
  (%skip-to (eql ch char)))

(declaim (inline skip1))
(defun skip1 (buffer)
  (declare (type buffer buffer))
  (incf (buffer-current buffer)))

(defun %read (buffer)
  (declare (type buffer buffer))
  (skip-to* buffer "\"{[tfn0123456789-]}")
  (case (buffer-current-char buffer)
    (#\" (read-string buffer))
    (#\{ (read-object buffer))
    (#\[ (read-array buffer))
    (#\t (incf (buffer-current buffer) 4) t)
    (#\f (incf (buffer-current buffer) 5) nil)
    (#\n (incf (buffer-current buffer) 4) nil)
    (t (read-number buffer))))

(defun read-string (buffer)
  (declare (type buffer buffer))
  (skip1 buffer)
  (let ((result (with-output-to-string (stream)
                  (loop for index from (buffer-current buffer) to (skip-to buffer #\")
                        for chr = (the standard-char (buffer-elt buffer index))
                        if (eql chr #\\)
                          do (write-char
                              (case (setf chr (buffer-elt buffer (incf index)))
                                (#\b #\Backspace)
                                (#\f #\Newline)
                                (#\n #\Newline)
                                (#\r #\Return)
                                (#\t #\Tab)
                                (t chr))
                              stream)
                        else
                          do (write-char chr stream)))))
    (skip1 buffer)
    (the string result)))

(defun read-object (buffer)
  (declare (type buffer buffer))
  (skip-to buffer #\{)
  (loop do (skip-to* buffer "\"}")
        until (buffer-current-char-eql buffer #\})
        nconc (list (make-keyword (read-string buffer))
                    (progn (skip-to buffer #\:)
                           (%read buffer)))))

(defun read-array (buffer)
  (declare (type buffer buffer))
  (skip1 buffer)
  (skip-to* buffer "]\"{[tfn0123456789-")
  (if (buffer-current-char-eql buffer #\])
      (progn (skip1 buffer) nil)
      (loop until (buffer-current-char-eql buffer #\])
            collecting (%read buffer)
            do (skip-to* buffer ",]["))))

(defun read-number (buffer &key rest)
  (declare (type buffer buffer))
  (let* ((start (buffer-current buffer))
         (end (1+ (if rest
                      (skip-to* buffer ",}]")
                      (skip-to* buffer ",}]."))))
         (subseqed (buffer-subseq buffer start end))
         (result (parse-integer subseqed)))
    (if (or rest (not (buffer-current-char-eql buffer #\.)))
        (values result (length subseqed))
        (progn (skip1 buffer)
               (+ result
                  (multiple-value-bind (result len)
                      (read-number buffer :rest t)
                    (/ result (expt 10 len))))))))


(declaim (inline integer-char-p))
(defun integer-char-p (char)
  (or (char<= #\0 char #\9)
      (char= char #\-)))

(defun parse1 (string &key (as :plist))
  (with-vector-parsing (string :dont-raise-eof-error t :unsafely t)
    (macrolet ((skip-spaces ()
                 `(skip* #\Space))
               (skip?-with-spaces (char)
                 `(progn
                    (skip-spaces)
                    (skip? ,char)
                    (skip-spaces)))
               (skip?-or-eof (char)
                 `(or (skip? ,char) (eofp))))
      (labels ((dispatch ()
                 (skip-spaces)
                 (match-case
                  ("{" (read-object))
                  ("\"" (read-string))
                  ("[" (read-array))
                  (otherwise (read-number))))
               (read-object ()
                 (skip-spaces)
                 (loop until (skip?-or-eof #\})
                       for key = (progn (advance) (read-string))
                       for value = (progn (skip-spaces) (advance) (skip-spaces) (dispatch))
                       do (skip?-with-spaces #\,)
                       if (eq as :alist)
                         collecting (cons key value)
                       else
                         nconc (list (make-keyword key) value)))
               (read-string ()
                 (with-output-to-string (stream)
                   (loop until (skip?-or-eof #\")
                         do (write-char
                             (the standard-char
                                  (match-case
                                   ("\\b" #\Backspace)
                                   ("\\f" #\Newline)
                                   ("\\n" #\Newline)
                                   ("\\r" #\Return)
                                   ("\\t" #\Tab)
                                   (otherwise (prog1 (current) (advance)))))
                             stream))))
               (read-array ()
                 (skip-spaces)
                 (loop until (skip?-or-eof #\])
                       collect (prog1 (dispatch)
                                 (skip?-with-spaces #\,))))
               (read-number (&optional rest-p)
                 (let ((start (the fixnum (pos))))
                   (bind (num-str (skip-while integer-char-p))
                     (let ((num (the fixnum (or (parse-integer num-str :junk-allowed t) 0))))
                       (cond
                         (rest-p
                          (the rational (/ num (the fixnum (expt 10 (- (pos) start))))))
                         ((skip? #\.)
                          (the rational (+ num (the rational (read-number t)))))
                         (t (the fixnum num))))))))
        (skip-spaces)
        (return-from parse1 (dispatch))))))

(defun make-keyword (str)
  (intern str #.(find-package :keyword)))
