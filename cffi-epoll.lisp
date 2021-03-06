;;
;;  cffi-epoll  -  Common Lisp wrapper for Linux epoll syscall
;;
;;  Copyright 2017 Thomas de Grivel <thoxdg@gmail.com>
;;
;;  Permission to use, copy, modify, and distribute this software for any
;;  purpose with or without fee is hereby granted, provided that the above
;;  copyright notice and this permission notice appear in all copies.
;;
;;  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
;;  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
;;  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
;;  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
;;  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
;;  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
;;  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
;;

(in-package :cffi-epoll)

(defcfun ("epoll_create" c-epoll-create) :int
  (size :int))

(defun create (&optional (size 10))
  (let ((fd (c-epoll-create size)))
    (when (< fd 0)
      (error-errno "epoll_create"))
    fd))

(defmacro with ((fdvar &optional (size 10)) &body body)
  (let ((fd (gensym "FD-")))
    `(let ((,fd (create ,size)))
       (unwind-protect (let ((,fdvar ,fd)) ,@body)
         (unistd:close ,fd)))))

(defcfun ("epoll_ctl" c-epoll-ctl) :int
  (epfd :int)
  (op :int)
  (fd :int)
  (event (:pointer (:struct epoll-event))))

(defun ctl (epfd op fd events &key data-ptr data-fd data-u32 data-u64)
  (with-foreign-object (evt '(:struct epoll-event))
    (setf (foreign-slot-value evt '(:struct epoll-event) 'events) events)
    (let ((data (foreign-slot-value evt '(:struct epoll-event) 'data)))
      (with-foreign-slots ((ptr fd u32 u64) data (:union epoll-data))
        (cond (data-ptr (setf ptr data-ptr))
              (data-fd  (setf fd  data-fd))
              (data-u32 (setf u32 data-u32))
              (data-u64 (setf u64 data-u64)))))
    (let ((r (c-epoll-ctl epfd op fd evt)))
      (when (< r 0)
        (error-errno "epoll_ctl"))
      r)))

(defun add (epfd fd events &key data-ptr data-fd data-u32 data-u64)
  (ctl epfd +ctl-add+ fd events
       :data-ptr data-ptr
       :data-fd  data-fd
       :data-u32 data-u32
       :data-u64 data-u64))

(defun mod (epfd fd events &key data-ptr data-fd data-u32 data-u64)
  (ctl epfd +ctl-mod+ fd events
       :data-ptr data-ptr
       :data-fd  data-fd
       :data-u32 data-u32
       :data-u64 data-u64))

(defun del (epfd fd)
  (ctl epfd +ctl-del+ fd 0))

(defcfun ("epoll_wait" c-epoll-wait) :int
  (epfd :int)
  (events (:pointer (:struct epoll-event)))
  (maxevents :int)
  (timeout :int))

(defmacro wait ((events-var fd-var epfd &optional
                            (max-events 1024)
                            (timeout 60000))
                &body body)
  (let ((events (gensym "EVENTS-"))
        (evt (gensym "EVT-"))
        (e-data (gensym "E-DATA-"))
        (n (gensym "N-"))
        (i (gensym "I-"))
        (g-max-events (gensym "MAX-EVENTS-")))
    `(let ((,g-max-events ,max-events))
       (with-foreign-object (,events '(:struct epoll-event) ,g-max-events)
         (loop
            (let ((,n (c-epoll-wait ,epfd ,events ,g-max-events ,timeout)))
              (when (< ,n 0)
                (handler-case
                    (error-errno "epoll_wait")
                  (errno-error (condition)
                    (when (= +eintr+ (errno-error-errno condition))
                      (continue)))))
              (dotimes (,i ,n)
                (let* ((,evt (mem-aptr ,events '(:struct epoll-event) ,i))
                       (,events-var (foreign-slot-value
                                     ,evt '(:struct epoll-event) 'events))
                       (,e-data (foreign-slot-value
                                 ,evt '(:struct epoll-event) 'data))
                       (,fd-var (foreign-slot-value
                                 ,e-data '(:union epoll-data) 'fd)))
                  ,@body))
              (return)))))))
