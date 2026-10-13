{# Scheduled exports: email (or Slack, a webhook, ...) a PDF of the report on a cron schedule.

   These are not part of a report's contents. Sigma keeps them in their own resource
   (`/v2/reports/{reportId}/schedules`), and the schema for `POST /v2/reports` has no schedule or cron
   field, and no scheduled trigger for actions. So a schedule is compiled here as data, carried on the spec
   beside `contents` (`report(schedules=[...])`), and applied by `scripts/export_reports.py --push` once the
   report exists. The macros still never call Sigma. A schedule is matched to the one already in Sigma by
   its name (Sigma's `title`), so renaming one creates a new schedule and leaves the old in place.

     {% set weekly = sigma_report.schedule(
          'Weekly sales',
          cron='0 8 * * 1',
          timezone='America/New_York',
          to=['finance@example.com', {'teamId': '<your-team-id>'}],
          message='This week''s numbers.',
          only_if_not_empty=orders,
        ) %}

   Sigma exports a report only as a whole PDF. Anything the macro doesn't model (control values, attachment
   merging, a column condition) goes in `options`, deep-merged onto Sigma's `configV2`. #}


{# A recipient as Sigma's `target` entry. A string containing `@` is an email address. Anything else (a
   team, a Slack conversation, a webhook, a Google Drive folder) is a Sigma target mapping such as
   {'teamId': ...} or {'slackConversationId': ...}, used as written. #}
{% macro _recipient(value) %}
{% if value is mapping %}
  {% if value | length == 0 %}
    {% do sigma_report.fail('schedule', "a recipient mapping must not be empty.") %}
  {% endif %}
  {% do return(value) %}
{% elif value is string and '@' in value %}
  {% do return({"email": value}) %}
{% endif %}
{% do sigma_report.fail('schedule', "a recipient is an email address or a Sigma target mapping (teamId, slackConversationId, webhookUrl, ...), got " ~ value) %}
{% endmacro %}


{% macro schedule(name, cron, to, timezone='UTC', message='', layout='portrait', scale=none, include_link=true, run_as_recipient=false, only_if_not_empty=none, only_if_empty=none, options={}) %}
{% if not name %}
  {% do sigma_report.fail('schedule', "name is required: it is the title Sigma shows, and how a re-push finds the schedule to update.") %}
{% endif %}
{% set parts = cron.split() if cron is string else [] %}
{% if parts | length != 5 %}
  {% do sigma_report.fail('schedule', "cron must be a 5-field cron expression such as '0 8 * * 1', got " ~ cron) %}
{% endif %}
{% if to is string or to is mapping or to is not iterable or to | length == 0 %}
  {% do sigma_report.fail('schedule', "to must be a non-empty list of recipients.") %}
{% endif %}
{% if layout not in ['portrait', 'landscape'] %}
  {% do sigma_report.fail('schedule', "layout must be 'portrait' or 'landscape', got '" ~ layout ~ "'.") %}
{% endif %}
{% if scale is not none and (scale is not number or scale <= 0) %}
  {% do sigma_report.fail('schedule', "scale must be a positive number, got " ~ scale) %}
{% endif %}
{% if only_if_not_empty is not none and only_if_empty is not none %}
  {% do sigma_report.fail('schedule', "pass at most one of only_if_not_empty= / only_if_empty=.") %}
{% endif %}
{% if options is not mapping %}
  {% do sigma_report.fail('schedule', "options must be a mapping of Sigma's own configV2 fields.") %}
{% endif %}

{% set targets = [] %}
{% for recipient in to %}{% do targets.append(sigma_report._recipient(recipient)) %}{% endfor %}

{% set pdf = {"type": "PDF", "layout": layout} %}
{% if scale is not none %}{% do pdf.update({"scaleFactor": scale}) %}{% endif %}
{% set config = {
  "title": name,
  "messageBody": message,
  "exportAttachments": [{"formatOptions": pdf}],
  "includeLink": include_link,
  "runAsRecipient": run_as_recipient,
} %}
{% if only_if_not_empty is not none %}
  {% do config.update({"conditionOptions": {"type": "workbook", "condition": {"type": "isNotEmpty", "elementId": sigma_report._ref(only_if_not_empty, 'schedule', 'only_if_not_empty')}}}) %}
{% elif only_if_empty is not none %}
  {% do config.update({"conditionOptions": {"type": "workbook", "condition": {"type": "isEmpty", "elementId": sigma_report._ref(only_if_empty, 'schedule', 'only_if_empty')}}}) %}
{% endif %}
{% set config = sigma_report.deep_merge(config, options) %}

{% do return({"target": targets, "schedule": {"cronSpec": cron, "timezone": timezone}, "configV2": config}) %}
{% endmacro %}
