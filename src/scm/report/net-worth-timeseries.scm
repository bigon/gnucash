;; -*-scheme-*-

;; net-worth-timeseries.scm
;; Display a simple time series for net worth
;; by Robert Merkel (rgmerk@mira.net)

(gnc:support "report/net-worth-timeseries.scm")
(gnc:depend  "report-html.scm")
(gnc:depend  "date-utilities.scm")

(let ((optname-from-date (N_ "From"))
      (optname-to-date (N_ "To"))
      (optname-stepsize (N_ "Step Size"))
      (optname-report-currency (N_ "Report's currency"))

      (optname-accounts (N_ "Accounts"))

      (optname-sep-bars (N_ "Show Asset & Liability bars"))
      (optname-net-bars (N_ "Show net worth bars"))
      (optname-plot-width (N_ "Plot Width"))
      (optname-plot-height (N_ "Plot Height")))

  (define (options-generator)    
    (let* ((options (gnc:new-options)) 
           ;; This is just a helper function for making options.
           ;; See gnucash/src/scm/options.scm for details.
           (add-option 
            (lambda (new-option)
              (gnc:register-option options new-option))))

      (gnc:options-add-date-interval!
       options gnc:pagename-general
       optname-from-date optname-to-date "a")

      (gnc:options-add-interval-choice! 
       options gnc:pagename-general optname-stepsize "b" 'MonthDelta)

      (add-option
       (gnc:make-account-list-option
	gnc:pagename-accounts optname-accounts
	"c"
	(N_ "Report on these accounts, if chosen account level allows.")
	(lambda ()
	  (filter
	   (lambda (account) (not (gnc:account-is-inc-exp? account)))
	   (gnc:group-get-subaccounts (gnc:get-current-group))))
	(lambda (accounts)
	  (list #t
		(filter (lambda (account)
			  (not (gnc:account-is-inc-exp? account)))
			accounts)))
	#t))

      (gnc:options-add-currency! 
       options gnc:pagename-general optname-report-currency "d")
      
      (add-option
       (gnc:make-simple-boolean-option
        gnc:pagename-display optname-sep-bars
        "a" (N_ "Show the Asset and the Liability/Equity bars?") #t))

      (add-option
       (gnc:make-simple-boolean-option
        gnc:pagename-display optname-net-bars
        "b" (N_ "Show a Net Worth bar?") #t))


      (gnc:options-add-plot-size! 
       options gnc:pagename-display 
       optname-plot-width optname-plot-height "c" 500 400)

      (gnc:options-set-default-section options gnc:pagename-general)

      options))
  
  ;; This is the rendering function. It accepts a database of options
  ;; and generates an object of type <html-document>.  See the file
  ;; report-html.txt for documentation; the file report-html.scm
  ;; includes all the relevant Scheme code. The option database passed
  ;; to the function is one created by the options-generator function
  ;; defined above.
  (define (net-worth-series-renderer report-obj)

    ;; These are some helper functions for looking up option values.
    (define (get-op section name)
      (gnc:lookup-option (gnc:report-options report-obj) section name))
    
    (define (op-value section name)
      (gnc:option-value (get-op section name)))

    (define (collector-fn accounts dates)
      (define (single-account-get-balance account tp)
	(begin 
	  (gnc:debug "account" account)
	  (gnc:debug "tp" tp)
	  (gnc:account-get-comm-balance-at-date 
	   account tp #f)))
      (define (accounts-get-balance tp the-accounts)
	(gnc:accounts-get-comm-total-assets
	 the-accounts (lambda (account)
			   (single-account-get-balance account tp))))

      (map (lambda (date) (accounts-get-balance date accounts))
	   dates))
       

    (define (collector-to-double-fn report-currency exchange-fn)
      (lambda (commodity-collector)
        (gnc:numeric-to-double
         (gnc:gnc-monetary-amount
          (gnc:sum-collector-commodity commodity-collector
                                       report-currency 
                                       exchange-fn)))))

    (define (collector-combine asset-collector liability-collector)
      (let ((new-collector (gnc:make-commodity-collector)))
	(new-collector 'merge asset-collector #f)
	(new-collector 'merge liability-collector #f)
	new-collector))
	

    (let* ((to-date-tp (gnc:timepair-end-day-time 
			(gnc:date-option-absolute-time
                         (op-value gnc:pagename-general optname-to-date))))
	   (from-date-tp (gnc:timepair-start-day-time 
			  (gnc:date-option-absolute-time
                           (op-value gnc:pagename-general optname-from-date))))
	   (interval (op-value gnc:pagename-general optname-stepsize))
	   (accounts (op-value gnc:pagename-accounts optname-accounts))
	   (classified-accounts (gnc:decompose-accountlist accounts))
	   (asset-accounts
	    (assoc-ref classified-accounts 'asset))
	   (liability-equity-accounts
	    (append
	     (assoc-ref classified-accounts 'liability)
	     (assoc-ref classified-accounts 'equity)))
           (report-currency (op-value gnc:pagename-general
                                      optname-report-currency))

	   (show-sep? (op-value gnc:pagename-display optname-sep-bars))
	   (show-net? (op-value gnc:pagename-display optname-net-bars))
	   (height (op-value gnc:pagename-display optname-plot-height))
	   (width (op-value gnc:pagename-display optname-plot-width))

	   (document (gnc:make-html-document))
	   (chart (gnc:make-html-barchart))
	   (exchange-alist (gnc:make-exchange-alist
			    report-currency to-date-tp))
	   (exchange-fn-internal (gnc:make-exchange-function exchange-alist))
	   (exchange-fn (lambda (foreign)
                          (exchange-fn-internal foreign report-currency)))
	   (dates-list (gnc:make-date-list
                        (gnc:timepair-end-day-time from-date-tp) 
                        (gnc:timepair-end-day-time to-date-tp)
                        (eval interval)))
           (assets-collector-list (collector-fn asset-accounts dates-list))
	   (expense-collector-list
            (collector-fn liability-equity-accounts dates-list))
	   (net-collector-list
            (map collector-combine assets-collector-list
                 expense-collector-list))
	   (assets-list
            (map (collector-to-double-fn report-currency exchange-fn-internal)
                 assets-collector-list))
           (liability-list
            (map (collector-to-double-fn report-currency exchange-fn-internal)
                 expense-collector-list))
	   (net-list
	    (map (collector-to-double-fn report-currency exchange-fn-internal)
		 net-collector-list))
	   (date-string-list
	    (map gnc:timepair-to-datestring
		 dates-list)))

      (gnc:html-barchart-set-title! chart (_ "Net Worth Chart"))
      (gnc:html-barchart-set-subtitle!
       chart (sprintf #f
                      (_ "%s to %s")
                      (gnc:timepair-to-datestring from-date-tp) 
                      (gnc:timepair-to-datestring to-date-tp)))
      (gnc:html-barchart-set-width! chart width)
      (gnc:html-barchart-set-height! chart height)
      (gnc:html-barchart-set-row-labels! chart date-string-list)
      (gnc:html-barchart-set-y-axis-label!
       chart (gnc:commodity-get-mnemonic report-currency))
      ;; Determine whether we have enough space for horizontal labels
      ;; -- kind of a hack. Assumptions: y-axis labels and legend
      ;; require 200 pixels, and each x-axes label needs 60 pixels.
      (gnc:html-barchart-set-row-labels-rotated?! 
       chart (< (/ (- width 200) 
		   (length date-string-list)) 60))

      (if show-sep?
          (begin
            (gnc:html-barchart-append-column! chart assets-list)
            (gnc:html-barchart-append-column! chart liability-list)))
      (if show-net?
	  (gnc:html-barchart-append-column! 
	   chart net-list))
      (gnc:html-barchart-set-col-labels! 
       chart (append
	      (if show-sep?
		  (list (_ "Assets") (_ "Liabilities/Equity")) '())
	      (if show-net?
		  (list (_ "Net Worth")) '())))
      (gnc:html-barchart-set-col-colors! 
       chart (append
	      (if show-sep?
		  '("blue" "red") '())
	      (if show-net?
		  '("green") '())))
      
      (if show-sep?
	  (let ((urls
		 (list
		  (gnc:make-report-anchor
		   "Assets Over Time"
		   report-obj
		   (list 
		    (list gnc:pagename-display
			  "Use Stacked Bars" #t)
		    (list gnc:pagename-general
			  gnc:optname-reportname
			  (_ "Asset Chart"))))
		  (gnc:make-report-anchor
		   "Liabilities/Equity Over Time"
		   report-obj
		   (list 
		    (list gnc:pagename-display
			  "Use Stacked Bars" #t)
		    (list gnc:pagename-general
			  gnc:optname-reportname
			  (_ "Liability/Equity Chart")))))))
	    (gnc:html-barchart-set-button-1-bar-urls! 
	     chart urls)
	    (gnc:html-barchart-set-button-1-legend-urls! 
	     chart urls)))

      (gnc:html-document-add-object! document chart) 

      document))

  ;; Here we define the actual report with gnc:define-report
  (gnc:define-report

   'version 1

   'name (N_ "Net Worth Barchart")

   'menu-path (list gnc:menuname-asset-liability)

   'options-generator options-generator

   'renderer net-worth-series-renderer))
