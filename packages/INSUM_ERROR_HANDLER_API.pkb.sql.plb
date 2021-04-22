create or replace package body insum_error_handler_api is

gc_developer_todo_message constant varchar2(100) := 'DEVELOPER TODO: Provide better message in APEX Shared Components Text Messages for ';

/* Create a message using apex_lang. This message can be managed using Shared Components -> Text Messages in APEX 
   Autonomous Transaction to not commit any other transactions that may happen in page
*/
function create_and_return_text_message 
   (p_constraint_name varchar2
   ) return varchar2 is
    PRAGMA AUTONOMOUS_TRANSACTION;  
    l_message varchar2(4000) :=  gc_developer_todo_message || p_constraint_name ;
begin
   apex_lang.create_message
      (p_application_id  => v('APP_ID'),
       p_name            => p_constraint_name,
       p_language        => nvl(apex_util.get_preference('FSP_LANGUAGE_PREFERENCE'), 'en'),
       p_message_text    => l_message 
       );
       commit;
       return l_message;
end create_and_return_text_message;

function error_handler 
   (p_error in apex_error.t_error
   ) return apex_error.t_error_result is
    l_result          apex_error.t_error_result;
    l_reference_id    number;
    l_constraint_name varchar2(255);
begin
    l_result := apex_error.init_error_result (
                    p_error => p_error );

    -- If it's an internal error raised by APEX, like an invalid statement or
    -- code which can't be executed, the error text might contain security sensitive
    -- information. To avoid this security problem we can rewrite the error to
    -- a generic error message and log the original error message for further
    -- investigation by the help desk.
    if p_error.is_internal_error then
        -- mask all errors that are not common runtime errors (Access Denied
        -- errors raised by application / page authorization and all errors
        -- regarding session and session state)
        if not p_error.is_common_runtime_error then
            -- log error for example with an autonomous transaction and return
            -- l_reference_id as reference#
            -- l_reference_id := log_error (
            --                       p_error => p_error );
            --

            -- Change the message to the generic error message which doesn't expose
            -- any sensitive information.
            l_result.message         := 'An unexpected internal application error has occurred. '||
                                        'Please get in contact with XXX and provide '||
                                        'reference# '||to_char(l_reference_id, '999G999G999G990')||
                                        ' for further investigation.';
            l_result.additional_info := null;
        end if;
    else
        -- Always show the error as inline error
        -- Note: If you have created manual tabular forms (using the package
        --       apex_item/htmldb_item in the SQL statement) you should still
        --       use "On error page" on that pages to avoid loosing entered data
        l_result.display_location := case
                                       when l_result.display_location = apex_error.c_on_error_page then apex_error.c_inline_in_notification
                                       else l_result.display_location
                                     end;

        --
        -- Note: If you want to have friendlier ORA error messages, you can also define
        --       a text message with the name pattern APEX.ERROR.ORA-number
        --       There is no need to implement custom code for that.
        --

        -- If it's a constraint violation like
        --
        --   -) ORA-00001: unique constraint violated
        --   -) ORA-02091: transaction rolled back (-> can hide a deferred constraint)
        --   -) ORA-02290: check constraint violated
        --   -) ORA-02291: integrity constraint violated - parent key not found
        --   -) ORA-02292: integrity constraint violated - child record found
        --
        -- we try to get a friendly error message from our constraint lookup configuration.
        -- If we don't find the constraint in our lookup table we fallback to
        -- the original ORA error message.
        if p_error.ora_sqlcode in (-1, -2091, -2290, -2291, -2292) then
            l_constraint_name := apex_error.extract_constraint_name (
                                     p_error => p_error );
            /*
            begin
                select message
                  into l_result.message
                  from constraint_lookup
                 where constraint_name = l_constraint_name;
            exception when no_data_found then null; -- not every constraint has to be in our lookup table
            end;
            */

            -- Instant Tip - Error handler function 
            -- Random Thoughts: I need to 'develop' some patience...fast... - Demetri Martin

            l_result.message := apex_lang.message(l_constraint_name);
                        
            if l_result.message = l_constraint_name then
               l_result.message := create_and_return_text_message (p_constraint_name => l_constraint_name);
            end if;   

            -- Random Thoughts: Every pizza is a personal pizza if you try hard and believe in yourself.. - Demetri Martin
            -- Instant Tip - Error handler function End      
        end if;

        -- If an ORA error has been raised, for example a raise_application_error(-20xxx, '...')
        -- in a table trigger or in a PL/SQL package called by a process and we
        -- haven't found the error in our lookup table, then we just want to see
        -- the actual error text and not the full error stack with all the ORA error numbers.
        if p_error.ora_sqlcode is not null and l_result.message = p_error.message then
            l_result.message := apex_error.get_first_ora_error_text (
                                    p_error => p_error );
        end if;

        -- If no associated page item/tabular form column has been set, we can use
        -- apex_error.auto_set_associated_item to automatically guess the affected
        -- error field by examine the ORA error for constraint names or column names.
        if l_result.page_item_name is null and l_result.column_alias is null then
            apex_error.auto_set_associated_item (
                p_error        => p_error,
                p_error_result => l_result );
        end if;
    end if;

    return l_result;
end error_handler;

end insum_error_handler_api;
