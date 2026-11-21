BEGIN;

CREATE OR REPLACE FUNCTION public.audit_alert_rule_changes()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.min_value IS DISTINCT FROM NEW.min_value
       OR OLD.max_value IS DISTINCT FROM NEW.max_value
       OR OLD.is_active IS DISTINCT FROM NEW.is_active THEN

        INSERT INTO public.alert_rule_audit (
            rule_id,
            old_min_value,
            new_min_value,
            old_max_value,
            new_max_value,
            old_is_active,
            new_is_active,
            changed_at,
            changed_by
        )
        VALUES (
            OLD.id,
            OLD.min_value,
            NEW.min_value,
            OLD.max_value,
            NEW.max_value,
            OLD.is_active,
            NEW.is_active,
            clock_timestamp(),
            current_user
        );

        NEW.updated_at := clock_timestamp();
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_alert_rule_changes
BEFORE UPDATE OF min_value, max_value, is_active
ON public.alert_rules
FOR EACH ROW
EXECUTE FUNCTION public.audit_alert_rule_changes();

COMMIT;
