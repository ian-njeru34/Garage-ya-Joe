-- Owner-controlled classification for statement rows that are not customer/supplier payments.
-- Classification is not verification and does not create or post accounting entries.
alter table public.payment_statement_lines
 add column if not exists review_category text,
 add column if not exists review_note text,
 add column if not exists reviewed_by uuid references public.profiles(id) on delete set null,
 add column if not exists reviewed_at timestamptz;
alter table public.payment_statement_lines drop constraint if exists payment_statement_lines_status_check;
alter table public.payment_statement_lines add constraint payment_statement_lines_status_check
 check(status in('pending','verified','unmatched','duplicate_reference','duplicate_statement_reference','already_verified','amount_mismatch','date_mismatch','currency_mismatch','invalid_reference','classified'));
alter table public.payment_statement_lines drop constraint if exists payment_statement_lines_review_category_check;
alter table public.payment_statement_lines add constraint payment_statement_lines_review_category_check
 check(review_category is null or review_category in('bank_charge','account_transfer','cash_deposit','refund_or_reversal','loan_or_financing','other_non_payment'));
create or replace function public.owner_classify_statement_line(
 p_business_id uuid,p_statement_line_id uuid,p_category text,p_note text
) returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_line public.payment_statement_lines%rowtype;v_is_owner boolean;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501';end if;
 select exists(select 1 from public.user_roles where user_id=v_uid and business_id=p_business_id and role_code='owner') into v_is_owner;
 if not v_is_owner then raise exception 'Only the business owner can classify unmatched statement entries.' using errcode='42501';end if;
 if p_category not in('bank_charge','account_transfer','cash_deposit','refund_or_reversal','loan_or_financing','other_non_payment') then raise exception 'Choose a valid statement category';end if;
 select * into v_line from public.payment_statement_lines where business_id=p_business_id and id=p_statement_line_id for update;
 if not found then raise exception 'Statement entry not found';end if;
 if v_line.status not in('unmatched','invalid_reference','already_verified') then raise exception 'Only unmatched or unrecognised statement entries can be classified';end if;
 if length(btrim(coalesce(p_note,'')))<5 then raise exception 'Enter a brief explanation of at least five characters';end if;
 update public.payment_statement_lines set status='classified',review_category=p_category,review_note=left(btrim(p_note),1000),reviewed_by=v_uid,reviewed_at=now(),review_reason='Owner classified as '||replace(p_category,'_',' ') where id=p_statement_line_id and business_id=p_business_id;
end $$;
revoke all on function public.owner_classify_statement_line(uuid,uuid,text,text) from public,anon;
grant execute on function public.owner_classify_statement_line(uuid,uuid,text,text) to authenticated;
