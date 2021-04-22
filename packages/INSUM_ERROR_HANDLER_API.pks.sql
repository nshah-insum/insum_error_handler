create or replace package insum_error_handler_api is


function error_handler 
   (p_error in apex_error.t_error
   ) return apex_error.t_error_result
;    


end insum_error_handler_api;
