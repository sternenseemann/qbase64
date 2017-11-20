(in-package #:qbase64)

;;; stream mixin

(defclass stream-mixin ()
  ((openp :accessor stream-open-p :initform t)))

(defmethod open-stream-p ((stream stream-mixin))
  (stream-open-p stream))

(defmethod close ((stream stream-mixin) &key abort)
  (declare (ignore abort))
  (setf (stream-open-p stream) nil))

(defmethod input-stream-p ((stream stream-mixin))
  nil)

(defmethod output-stream-p ((stream stream-mixin))
  nil)

;;; char-stripping-stream

(defclass char-stripping-stream (stream-mixin fundamental-character-input-stream trivial-gray-stream-mixin)
  ((underlying-stream :initarg :underlying-stream)
   (strip-char :initform #\Newline :initarg :strip-char)
   (buffer)
   (buffer-start :initform 0)
   (buffer-end :initform 0)))

(defmethod initialize-instance :after ((stream char-stripping-stream) &key)
  (with-slots (underlying-stream buffer)
      stream
    (setf buffer (make-array 1
                             :element-type (stream-element-type underlying-stream)
                             :adjustable t))))

(defmethod input-stream-p ((stream char-stripping-stream))
  t)

(defmethod stream-element-type ((stream char-stripping-stream))
  (stream-element-type (slot-value stream 'underlying-stream)))

(defmethod stream-read-char ((stream char-stripping-stream))
  (bind:bind (((:slots underlying-stream buffer strip-char buffer-start buffer-end)
               stream)
              ((:symbol-macrolet buffer-length) (- buffer-end buffer-start)))
    (when (plusp buffer-length)
      (loop
         for i from buffer-start below buffer-end
         for char = (char buffer i)
         while (char= char strip-char)
         finally (if (= i buffer-end)
                     (setf buffer-start 0 buffer-end 0)
                     (progn
                       (setf buffer-start i)
                       (return-from stream-read-char char)))))
    (loop
       for char = (read-char underlying-stream nil :eof)
       while (and (characterp char) (char= char strip-char))
       finally (return char))))

(defmethod stream-unread-char ((stream char-stripping-stream) char)
  (bind:bind (((:slots underlying-stream buffer buffer-start buffer-end)
               stream))
    (cond
      ((plusp buffer-start)
       (setf (char buffer (decf buffer-start)) char))
      ((= buffer-start buffer-end)
       (setf (char buffer 0) char)
       (incf buffer-end))
      (t
       (when (= (length buffer) buffer-end)
         (setf buffer (adjust-array buffer (1+ (length buffer)))))
       (replace buffer buffer
                :start1 1 :end1 (1+ buffer-end)
                :start2 0 :end2 buffer-end)
       (setf (char buffer 0) char)))
    nil))

(defmethod stream-read-sequence ((stream char-stripping-stream) string start end &key)
  (declare (type char-stripping-stream stream)
           (type string string)
           (type positive-fixnum start end))
  (declare (optimize speed))
  (bind:bind (((:slots underlying-stream buffer strip-char buffer-start buffer-end)
               stream)
              ((:symbol-macrolet output-space) (- end start))
              ((:symbol-macrolet buffer-length) (- buffer-end buffer-start)))
    (declare (type stream underlying-stream)
             (type string buffer)
             (type positive-fixnum buffer-start buffer-end))
    (loop
       with eof-p = nil
       while (and (not eof-p) (plusp output-space))
       do (progn
            (when (plusp buffer-length)
              (loop
                 for i of-type positive-fixnum from buffer-start
                 with j of-type positive-fixnum = start
                 while (and (< i buffer-end) (< j end))
                 for buffer-char = (char buffer i)
                 if (char/= buffer-char strip-char)
                 do
                   (setf (char string j) buffer-char)
                   (incf j)
                 finally (setf buffer-start i start j)))
            (when (zerop buffer-length)
              (setf buffer-start 0 buffer-end 0))
            (when (plusp output-space)
              (when (< (length buffer) output-space)
                (setf buffer (adjust-array buffer output-space)))
              (setf buffer-end (read-sequence buffer underlying-stream :start buffer-end))
              (when (zerop buffer-end)
                (setf eof-p t)))))
    start))