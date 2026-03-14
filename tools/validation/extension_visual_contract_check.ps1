param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root

$reportPath = Join-Path $Root 'tools/validation/extension_visual_contract.txt'
$logPath = Join-Path $Root '_proof/phase40_38_extension_visual_run.log'
$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
  throw "Missing canonical launcher: $launcher"
}

$oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
$oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
$oldVisual = $env:NGK_WIDGET_VISUAL_BASELINE
$oldExtVisual = $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE
$oldLane = $env:NGK_WIDGET_SANDBOX_LANE

try {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
  $env:NGK_WIDGET_SANDBOX_DEMO = '0'
  $env:NGK_WIDGET_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = '1'
  $env:NGK_WIDGET_SANDBOX_LANE = 'extension'

  $out = & $launcher -Config Debug -PassArgs @('--extension-visual-baseline', '--sandbox-extension') 2>&1
  $txt = ($out | Out-String)
  $exitCode = $LASTEXITCODE
  $txt | Set-Content -Path $logPath -Encoding UTF8

  $widgetExe = '(unknown)'
  foreach ($line in ($txt -split "`r?`n")) {
    if ($line -like 'LAUNCH_EXE=*') {
      $widgetExe = $line.Substring(11).Trim()
      break
    }
  }

  function HasToken([string]$token) {
    return $txt -match [regex]::Escape($token)
  }

  $checks = [ordered]@{
    extension_mode_active = (HasToken 'widget_extension_mode_active=1')
    extension_lane_selected = (HasToken 'widget_sandbox_lane=extension')
    extension_presentation_variant_defined = (HasToken 'widget_extension_presentation_variant=primary_summary_badge_emphasis_v1')
    extension_data_shape_defined = (HasToken 'widget_extension_data_shape=card_display_v1')
    extension_composition_model = (HasToken 'widget_extension_composition_model=primary_info_card+secondary_placeholder')
    extension_slot_primary_visible = (HasToken 'widget_extension_slot_primary_visible=1')
    extension_slot_secondary_visible = (HasToken 'widget_extension_slot_secondary_visible=1')
    extension_label_present = (HasToken 'widget_extension_mode_label_present=1')
    extension_label_text_fixed = (HasToken 'widget_extension_mode_label_text=Extension mode: active')
    extension_info_card_present = (HasToken 'widget_extension_info_card_present=1')
    extension_info_card_title_fixed = (HasToken 'widget_extension_info_card_title=Runtime Control Card')
    extension_info_card_text_fixed = (HasToken 'widget_extension_info_card_text=Primary controls and status')
    extension_info_card_summary_default = (HasToken 'widget_extension_info_card_summary=State summary: inactive')
    extension_info_card_detail_default = (HasToken 'widget_extension_info_card_detail=Action: waiting for toggle')
    extension_card_data_secondary_state_default = (HasToken 'widget_extension_card_data_secondary_state=inactive')
    extension_card_data_summary_text_default = (HasToken 'widget_extension_card_data_summary_text=State summary: inactive')
    extension_card_data_badge_variant_default = (HasToken 'widget_extension_card_data_badge_variant=neutral')
    extension_card_data_detail_text_default = (HasToken 'widget_extension_card_data_detail_text=Action: waiting for toggle')
    extension_layout_mode_default = (HasToken 'widget_extension_layout_mode=compact')
    extension_layout_placeholder_height_default = (HasToken 'widget_extension_layout_placeholder_height=16')
    extension_layout_mode_selector_fixed = (HasToken 'widget_extension_layout_mode_selector=secondary_placeholder_state')
    extension_content_update_mode_fixed = (HasToken 'widget_extension_content_update_mode=interaction_driven_detail_v1')
    extension_card_data_detail_source_fixed = (HasToken 'widget_extension_card_data_detail_source=secondary_toggle_interaction')
    extension_parent_visibility_rule_name_fixed = (HasToken 'widget_extension_parent_visibility_rule_name=parent_secondary_indicator_visibility_v1')
    extension_parent_visibility_rule_owner_fixed = (HasToken 'widget_extension_parent_visibility_rule_owner=extension_parent_state')
    extension_parent_visibility_rule_target_fixed = (HasToken 'widget_extension_parent_visibility_rule_target=secondary_indicator_v1')
    extension_parent_visibility_rule_state_default = (HasToken 'widget_extension_parent_visibility_rule_state=hidden')
    extension_parent_ordering_rule_name_fixed = (HasToken 'widget_extension_parent_ordering_rule_name=parent_subcomponent_ordering_v1')
    extension_parent_ordering_rule_owner_fixed = (HasToken 'widget_extension_parent_ordering_rule_owner=extension_parent_state')
    extension_parent_ordering_rule_state_default = (HasToken 'widget_extension_parent_ordering_rule_state=status_first')
    extension_parent_ordering_child_dependency_none = (HasToken 'widget_extension_parent_ordering_child_dependency=none')
    extension_parent_orchestration_rule_name_fixed = (HasToken 'widget_extension_parent_orchestration_rule_name=parent_emphasis_bridge_v1')
    extension_parent_orchestration_rule_owner_fixed = (HasToken 'widget_extension_parent_orchestration_rule_owner=extension_parent_state')
    extension_parent_orchestration_rule_state_default = (HasToken 'widget_extension_parent_orchestration_rule_state=inactive')
    extension_parent_orchestration_child_dependency_none = (HasToken 'widget_extension_parent_orchestration_child_dependency=none')
    extension_layout_container_name_fixed = (HasToken 'widget_extension_layout_container_name=sandbox_extension_panel')
    extension_layout_container_role_fixed = (HasToken 'widget_extension_layout_container_role=subcomponent_layout_surface')
    extension_layout_container_owner_fixed = (HasToken 'widget_extension_layout_container_owner=extension_parent_state')
    extension_layout_container_child_order_fixed = (HasToken 'widget_extension_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent')
    extension_layout_container_child_count_fixed = (HasToken 'widget_extension_layout_container_child_count=3')
    extension_layout_header_name_fixed = (HasToken 'widget_extension_layout_container_header_band_name=sandbox_extension_header_band')
    extension_layout_header_role_fixed = (HasToken 'widget_extension_layout_container_header_band_role=layout_header_region')
    extension_layout_header_owner_fixed = (HasToken 'widget_extension_layout_container_header_band_owner=extension_parent_state')
    extension_layout_header_title_fixed = (HasToken 'widget_extension_layout_container_header_band_title=Runtime Panel')
    extension_layout_header_summary_default = (HasToken 'widget_extension_layout_container_header_band_summary=Mode: secondary inactive')
    extension_layout_header_summary_owner_fixed = (HasToken 'widget_extension_layout_container_header_band_summary_owner=extension_parent_state')
    extension_layout_header_summary_child_dependency_none = (HasToken 'widget_extension_layout_container_header_band_summary_child_dependency=none')
    extension_layout_region_order_fixed = (HasToken 'widget_extension_layout_container_region_order=header_band,body_region,footer_strip')
    extension_layout_body_name_fixed = (HasToken 'widget_extension_layout_container_body_region_name=sandbox_extension_body_region')
    extension_layout_body_role_fixed = (HasToken 'widget_extension_layout_container_body_region_role=layout_body_region')
    extension_layout_body_owner_fixed = (HasToken 'widget_extension_layout_container_body_region_owner=extension_parent_state')
    extension_layout_body_title_fixed = (HasToken 'widget_extension_layout_container_body_region_title=State Overview')
    extension_layout_body_child_order_fixed = (HasToken 'widget_extension_layout_container_body_region_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent')
    extension_layout_body_child_count_fixed = (HasToken 'widget_extension_layout_container_body_region_child_count=3')
    extension_layout_body_child_dependency_none = (HasToken 'widget_extension_layout_container_body_region_child_dependency=none')
    extension_layout_footer_name_fixed = (HasToken 'widget_extension_layout_container_footer_strip_name=sandbox_extension_footer_strip')
    extension_layout_footer_role_fixed = (HasToken 'widget_extension_layout_container_footer_strip_role=layout_footer_region')
    extension_layout_footer_owner_fixed = (HasToken 'widget_extension_layout_container_footer_strip_owner=extension_parent_state')
    extension_layout_footer_title_fixed = (HasToken 'widget_extension_layout_container_footer_strip_title=Next Action')
    extension_layout_footer_value_fixed = (HasToken 'widget_extension_layout_container_footer_strip_value=Next action: ready')
    extension_layout_footer_status_owner_fixed = (HasToken 'widget_extension_layout_container_footer_strip_status_owner=extension_parent_state')
    extension_layout_footer_child_dependency_none = (HasToken 'widget_extension_layout_container_footer_strip_child_dependency=none')
    extension_layout_region_backgrounds_fixed = (HasToken 'widget_extension_layout_container_region_backgrounds=header:0.10,0.12,0.14,1.00|body:0.11,0.13,0.15,1.00|footer:0.10,0.12,0.14,1.00')
    extension_layout_header_integration_profile_fixed = (HasToken 'widget_extension_layout_container_header_integration_profile=panel_header_blend_v1')
    extension_layout_header_padding_refinement_fixed = (HasToken 'widget_extension_layout_container_header_padding_refinement=inner:9,5,9,4')
    extension_layout_header_text_legibility_fixed = (HasToken 'widget_extension_layout_container_header_text_legibility=title:17|summary:15')
    extension_layout_full_panel_cohesion_profile_fixed = (HasToken 'widget_extension_layout_container_full_panel_cohesion_profile=unified_compact_surface_v1')
    extension_layout_divider_language_fixed = (HasToken 'widget_extension_layout_container_divider_language=unified_control_card_surface_v1')
    extension_layout_region_spacing_rhythm_fixed = (HasToken 'widget_extension_layout_container_region_spacing_rhythm=header:11|body:11|footer:11')
    extension_layout_controls_integration_profile_fixed = (HasToken 'widget_extension_layout_container_controls_integration_profile=panel_controls_action_focus_v1')
    extension_layout_controls_surface_fixed = (HasToken 'widget_extension_layout_container_controls_surface=bg:0.12,0.16,0.19,1.00|label:0.12,0.16,0.19,1.00')
    extension_layout_controls_spacing_fixed = (HasToken 'widget_extension_layout_container_controls_spacing=label:22|input:42|row:66')
    extension_layout_controls_padding_refinement_fixed = (HasToken 'widget_extension_layout_container_controls_padding_refinement=row:6')
    extension_layout_footer_integration_profile_fixed = (HasToken 'widget_extension_layout_container_footer_integration_profile=panel_footer_blend_v1')
    extension_layout_footer_padding_refinement_fixed = (HasToken 'widget_extension_layout_container_footer_padding_refinement=inner:9,4,9,4')
    extension_layout_footer_text_legibility_fixed = (HasToken 'widget_extension_layout_container_footer_text_legibility=title:13|value:16')
    extension_layout_readability_profile_fixed = (HasToken 'widget_extension_layout_container_readability_profile=panel_calm_control_card_reconstruction_v1')
    extension_layout_readability_spacing_fixed = (HasToken 'widget_extension_layout_container_readability_spacing=panel:11|header:12|body:11|footer:11')
    extension_layout_readability_typography_fixed = (HasToken 'widget_extension_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22')
    extension_layout_text_contrast_profile_fixed = (HasToken 'widget_extension_layout_container_text_contrast_profile=calm_control_card_hierarchy_v1')
    extension_subcomponent_name_fixed = (HasToken 'widget_extension_subcomponent_name=status_chip_v1')
    extension_subcomponent_secondary_name_fixed = (HasToken 'widget_extension_subcomponent_secondary_name=secondary_indicator_v1')
    extension_subcomponent_tertiary_name_fixed = (HasToken 'widget_extension_subcomponent_tertiary_name=tertiary_marker_subcomponent')
    extension_subcomponent_coexistence_fixed = (HasToken 'widget_extension_subcomponent_coexistence=status_chip_v1+secondary_indicator_v1+tertiary_marker_subcomponent')
    extension_subcomponent_input_record_fixed = (HasToken 'widget_extension_subcomponent_input_record=status_chip_input_v1')
    extension_subcomponent_input_owner_fixed = (HasToken 'widget_extension_subcomponent_input_owner=extension_parent_state')
    extension_subcomponent_visible_default = (HasToken 'widget_extension_subcomponent_visible=1')
    extension_subcomponent_input_text_default = (HasToken 'widget_extension_subcomponent_input_text=System state: ready')
    extension_subcomponent_input_content_extra_line_default = (HasToken 'widget_extension_subcomponent_input_content_extra_line=Feedback: ready')
    extension_subcomponent_input_variant_default = (HasToken 'widget_extension_subcomponent_input_variant=neutral')
    extension_subcomponent_input_presentation_variant_default = (HasToken 'widget_extension_subcomponent_input_presentation_variant=base')
    extension_subcomponent_input_layout_variant_default = (HasToken 'widget_extension_subcomponent_input_layout_variant=compact')
    extension_subcomponent_input_layout_height_default = (HasToken 'widget_extension_subcomponent_input_layout_height=20')
    extension_subcomponent_input_interaction_boundary_state_default = (HasToken 'widget_extension_subcomponent_input_interaction_boundary_state=inactive')
    extension_subcomponent_input_parent_orchestration_rule_fixed = (HasToken 'widget_extension_subcomponent_input_parent_orchestration_rule=parent_emphasis_bridge_v1')
    extension_subcomponent_input_parent_orchestration_state_default = (HasToken 'widget_extension_subcomponent_input_parent_orchestration_state=inactive')
    extension_subcomponent_input_source_fixed = (HasToken 'widget_extension_subcomponent_input_source=secondary_placeholder_state')
    extension_subcomponent_secondary_input_record_fixed = (HasToken 'widget_extension_subcomponent_secondary_input_record=secondary_indicator_input_v1')
    extension_subcomponent_secondary_input_owner_fixed = (HasToken 'widget_extension_subcomponent_secondary_input_owner=extension_parent_state_secondary_indicator')
    extension_subcomponent_secondary_visible_default = (HasToken 'widget_extension_subcomponent_secondary_visible=0')
    extension_subcomponent_secondary_visibility_owner_fixed = (HasToken 'widget_extension_subcomponent_secondary_visibility_owner=extension_parent_state')
    extension_subcomponent_secondary_text_default = (HasToken 'widget_extension_subcomponent_secondary_input_text=Support line: inactive')
    extension_subcomponent_secondary_variant_default = (HasToken 'widget_extension_subcomponent_secondary_input_variant=neutral')
    extension_subcomponent_secondary_parent_orchestration_rule_fixed = (HasToken 'widget_extension_subcomponent_secondary_input_parent_orchestration_rule=parent_emphasis_bridge_v1')
    extension_subcomponent_secondary_parent_orchestration_state_default = (HasToken 'widget_extension_subcomponent_secondary_input_parent_orchestration_state=inactive')
    extension_subcomponent_secondary_source_fixed = (HasToken 'widget_extension_subcomponent_secondary_input_source=secondary_placeholder_state')
    extension_subcomponent_tertiary_input_record_fixed = (HasToken 'widget_extension_subcomponent_tertiary_input_record=tertiary_marker_input_v1')
    extension_subcomponent_tertiary_input_owner_fixed = (HasToken 'widget_extension_subcomponent_tertiary_input_owner=extension_parent_state_tertiary_marker')
    extension_subcomponent_tertiary_visible_default = (HasToken 'widget_extension_subcomponent_tertiary_visible=1')
    extension_subcomponent_tertiary_text_default = (HasToken 'widget_extension_subcomponent_tertiary_input_text=Note: idle')
    extension_subcomponent_tertiary_variant_default = (HasToken 'widget_extension_subcomponent_tertiary_input_variant=muted')
    extension_subcomponent_tertiary_source_fixed = (HasToken 'widget_extension_subcomponent_tertiary_input_source=extension_parent_state')
    extension_subcomponent_tertiary_parent_coexistence_rule_fixed = (HasToken 'widget_extension_subcomponent_tertiary_parent_coexistence_rule=parent_subcomponent_isolation_v1')
    extension_subcomponent_tertiary_parent_coexistence_state_fixed = (HasToken 'widget_extension_subcomponent_tertiary_parent_coexistence_state=active')
    extension_subcomponent_tertiary_child_dependency_none = (HasToken 'widget_extension_subcomponent_tertiary_child_dependency=none')
    extension_primary_summary_badge_variant_default = (HasToken 'widget_extension_primary_summary_badge_variant=neutral')
    extension_primary_summary_badge_selector_fixed = (HasToken 'widget_extension_primary_summary_badge_selector=secondary_placeholder_state')
    extension_primary_summary_default = (HasToken 'widget_extension_primary_summary_text=State summary: inactive')
    extension_render_card_data_shape_default = (HasToken 'widget_extension_render_card_data_shape=card_display_v1')
    extension_render_card_data_summary_default = (HasToken 'widget_extension_render_card_data_summary_text=State summary: inactive')
    extension_render_card_data_detail_default = (HasToken 'widget_extension_render_card_data_detail_text=Action: waiting for toggle')
    extension_render_parent_visibility_rule_name_fixed = (HasToken 'widget_extension_render_parent_visibility_rule_name=parent_secondary_indicator_visibility_v1')
    extension_render_parent_visibility_rule_owner_fixed = (HasToken 'widget_extension_render_parent_visibility_rule_owner=extension_parent_state')
    extension_render_parent_visibility_rule_target_fixed = (HasToken 'widget_extension_render_parent_visibility_rule_target=secondary_indicator_v1')
    extension_render_parent_visibility_rule_state_default = (HasToken 'widget_extension_render_parent_visibility_rule_state=hidden')
    extension_render_parent_ordering_rule_name_fixed = (HasToken 'widget_extension_render_parent_ordering_rule_name=parent_subcomponent_ordering_v1')
    extension_render_parent_ordering_rule_owner_fixed = (HasToken 'widget_extension_render_parent_ordering_rule_owner=extension_parent_state')
    extension_render_parent_ordering_rule_state_default = (HasToken 'widget_extension_render_parent_ordering_rule_state=status_first')
    extension_render_parent_ordering_child_dependency_none = (HasToken 'widget_extension_render_parent_ordering_child_dependency=none')
    extension_render_parent_orchestration_rule_name_fixed = (HasToken 'widget_extension_render_parent_orchestration_rule_name=parent_emphasis_bridge_v1')
    extension_render_parent_orchestration_rule_owner_fixed = (HasToken 'widget_extension_render_parent_orchestration_rule_owner=extension_parent_state')
    extension_render_parent_orchestration_rule_state_default = (HasToken 'widget_extension_render_parent_orchestration_rule_state=inactive')
    extension_render_layout_container_name_fixed = (HasToken 'widget_extension_render_layout_container_name=sandbox_extension_panel')
    extension_render_layout_container_role_fixed = (HasToken 'widget_extension_render_layout_container_role=subcomponent_layout_surface')
    extension_render_layout_container_owner_fixed = (HasToken 'widget_extension_render_layout_container_owner=extension_parent_state')
    extension_render_layout_container_child_order_fixed = (HasToken 'widget_extension_render_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent')
    extension_render_layout_container_child_count_fixed = (HasToken 'widget_extension_render_layout_container_child_count=3')
    extension_render_layout_header_name_fixed = (HasToken 'widget_extension_render_layout_container_header_band_name=sandbox_extension_header_band')
    extension_render_layout_header_role_fixed = (HasToken 'widget_extension_render_layout_container_header_band_role=layout_header_region')
    extension_render_layout_header_owner_fixed = (HasToken 'widget_extension_render_layout_container_header_band_owner=extension_parent_state')
    extension_render_layout_header_title_fixed = (HasToken 'widget_extension_render_layout_container_header_band_title=Runtime Panel')
    extension_render_layout_header_summary_default = (HasToken 'widget_extension_render_layout_container_header_band_summary=Mode: secondary inactive')
    extension_render_layout_header_summary_owner_fixed = (HasToken 'widget_extension_render_layout_container_header_band_summary_owner=extension_parent_state')
    extension_render_layout_header_summary_child_dependency_none = (HasToken 'widget_extension_render_layout_container_header_band_summary_child_dependency=none')
    extension_render_layout_region_order_fixed = (HasToken 'widget_extension_render_layout_container_region_order=header_band,body_region,footer_strip')
    extension_render_layout_body_name_fixed = (HasToken 'widget_extension_render_layout_container_body_region_name=sandbox_extension_body_region')
    extension_render_layout_body_role_fixed = (HasToken 'widget_extension_render_layout_container_body_region_role=layout_body_region')
    extension_render_layout_body_owner_fixed = (HasToken 'widget_extension_render_layout_container_body_region_owner=extension_parent_state')
    extension_render_layout_body_title_fixed = (HasToken 'widget_extension_render_layout_container_body_region_title=State Overview')
    extension_render_layout_body_child_order_fixed = (HasToken 'widget_extension_render_layout_container_body_region_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent')
    extension_render_layout_body_child_count_fixed = (HasToken 'widget_extension_render_layout_container_body_region_child_count=3')
    extension_render_layout_body_child_dependency_none = (HasToken 'widget_extension_render_layout_container_body_region_child_dependency=none')
    extension_render_layout_footer_name_fixed = (HasToken 'widget_extension_render_layout_container_footer_strip_name=sandbox_extension_footer_strip')
    extension_render_layout_footer_role_fixed = (HasToken 'widget_extension_render_layout_container_footer_strip_role=layout_footer_region')
    extension_render_layout_footer_owner_fixed = (HasToken 'widget_extension_render_layout_container_footer_strip_owner=extension_parent_state')
    extension_render_layout_footer_title_fixed = (HasToken 'widget_extension_render_layout_container_footer_strip_title=Next Action')
    extension_render_layout_footer_value_fixed = (HasToken 'widget_extension_render_layout_container_footer_strip_value=Next action: ready')
    extension_render_layout_footer_status_owner_fixed = (HasToken 'widget_extension_render_layout_container_footer_strip_status_owner=extension_parent_state')
    extension_render_layout_footer_child_dependency_none = (HasToken 'widget_extension_render_layout_container_footer_strip_child_dependency=none')
    extension_render_layout_region_backgrounds_fixed = (HasToken 'widget_extension_render_layout_container_region_backgrounds=header:0.10,0.12,0.14,1.00|body:0.11,0.13,0.15,1.00|footer:0.10,0.12,0.14,1.00')
    extension_render_header_integration_profile_fixed = (HasToken 'widget_extension_render_layout_container_header_integration_profile=panel_header_blend_v1')
    extension_render_header_padding_refinement_fixed = (HasToken 'widget_extension_render_layout_container_header_padding_refinement=inner:9,5,9,4')
    extension_render_header_text_legibility_fixed = (HasToken 'widget_extension_render_layout_container_header_text_legibility=title:17|summary:15')
    extension_render_full_panel_cohesion_profile_fixed = (HasToken 'widget_extension_render_layout_container_full_panel_cohesion_profile=unified_compact_surface_v1')
    extension_render_divider_language_fixed = (HasToken 'widget_extension_render_layout_container_divider_language=unified_control_card_surface_v1')
    extension_render_region_spacing_rhythm_fixed = (HasToken 'widget_extension_render_layout_container_region_spacing_rhythm=header:11|body:11|footer:11')
    extension_render_controls_integration_profile_fixed = (HasToken 'widget_extension_render_layout_container_controls_integration_profile=panel_controls_action_focus_v1')
    extension_render_controls_surface_fixed = (HasToken 'widget_extension_render_layout_container_controls_surface=bg:0.12,0.16,0.19,1.00|label:0.12,0.16,0.19,1.00')
    extension_render_controls_spacing_fixed = (HasToken 'widget_extension_render_layout_container_controls_spacing=label:22|input:42|row:66')
    extension_render_controls_padding_refinement_fixed = (HasToken 'widget_extension_render_layout_container_controls_padding_refinement=row:6')
    extension_render_footer_integration_profile_fixed = (HasToken 'widget_extension_render_layout_container_footer_integration_profile=panel_footer_blend_v1')
    extension_render_footer_padding_refinement_fixed = (HasToken 'widget_extension_render_layout_container_footer_padding_refinement=inner:9,4,9,4')
    extension_render_footer_text_legibility_fixed = (HasToken 'widget_extension_render_layout_container_footer_text_legibility=title:13|value:16')
    extension_render_readability_profile_fixed = (HasToken 'widget_extension_render_layout_container_readability_profile=panel_calm_control_card_reconstruction_v1')
    extension_render_readability_spacing_fixed = (HasToken 'widget_extension_render_layout_container_readability_spacing=panel:11|header:12|body:11|footer:11')
    extension_render_readability_typography_fixed = (HasToken 'widget_extension_render_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22')
    extension_render_text_contrast_profile_fixed = (HasToken 'widget_extension_render_layout_container_text_contrast_profile=calm_control_card_hierarchy_v1')
    extension_render_child_dependency_none = (HasToken 'widget_extension_render_subcomponent_child_dependency=none')
    extension_render_subcomponent_name_fixed = (HasToken 'widget_extension_render_subcomponent_name=status_chip_v1')
    extension_render_subcomponent_input_record_fixed = (HasToken 'widget_extension_render_subcomponent_input_record=status_chip_input_v1')
    extension_render_subcomponent_input_owner_fixed = (HasToken 'widget_extension_render_subcomponent_input_owner=extension_parent_state')
    extension_render_subcomponent_from_input_only = (HasToken 'widget_extension_render_subcomponent_from_input_only=1')
    extension_render_subcomponent_visible_default = (HasToken 'widget_extension_render_subcomponent_visible=1')
    extension_render_subcomponent_text_default = (HasToken 'widget_extension_render_subcomponent_text=System state: ready')
    extension_render_subcomponent_content_extra_line_default = (HasToken 'widget_extension_render_subcomponent_content_extra_line=Feedback: ready')
    extension_render_subcomponent_variant_default = (HasToken 'widget_extension_render_subcomponent_variant=neutral')
    extension_render_subcomponent_presentation_variant_default = (HasToken 'widget_extension_render_subcomponent_presentation_variant=base')
    extension_render_subcomponent_layout_variant_default = (HasToken 'widget_extension_render_subcomponent_layout_variant=compact')
    extension_render_subcomponent_layout_height_default = (HasToken 'widget_extension_render_subcomponent_layout_height=20')
    extension_render_subcomponent_interaction_boundary_state_default = (HasToken 'widget_extension_render_subcomponent_interaction_boundary_state=inactive')
    extension_render_subcomponent_parent_orchestration_state_default = (HasToken 'widget_extension_render_subcomponent_parent_orchestration_state=inactive')
    extension_render_subcomponent_secondary_name_fixed = (HasToken 'widget_extension_render_subcomponent_secondary_name=secondary_indicator_v1')
    extension_render_subcomponent_secondary_input_record_fixed = (HasToken 'widget_extension_render_subcomponent_secondary_input_record=secondary_indicator_input_v1')
    extension_render_subcomponent_secondary_input_owner_fixed = (HasToken 'widget_extension_render_subcomponent_secondary_input_owner=extension_parent_state_secondary_indicator')
    extension_render_subcomponent_secondary_from_input_only = (HasToken 'widget_extension_render_subcomponent_secondary_from_input_only=1')
    extension_render_subcomponent_secondary_visible_default = (HasToken 'widget_extension_render_subcomponent_secondary_visible=0')
    extension_render_subcomponent_secondary_rendered_default = (HasToken 'widget_extension_render_subcomponent_secondary_rendered=0')
    extension_render_subcomponent_secondary_visibility_owner_fixed = (HasToken 'widget_extension_render_subcomponent_secondary_visibility_owner=extension_parent_state')
    extension_render_subcomponent_secondary_text_default = (HasToken 'widget_extension_render_subcomponent_secondary_text=Support line: inactive')
    extension_render_subcomponent_secondary_variant_default = (HasToken 'widget_extension_render_subcomponent_secondary_variant=neutral')
    extension_render_subcomponent_secondary_parent_orchestration_state_default = (HasToken 'widget_extension_render_subcomponent_secondary_parent_orchestration_state=inactive')
    extension_render_subcomponent_tertiary_name_fixed = (HasToken 'widget_extension_render_subcomponent_tertiary_name=tertiary_marker_subcomponent')
    extension_render_subcomponent_tertiary_input_record_fixed = (HasToken 'widget_extension_render_subcomponent_tertiary_input_record=tertiary_marker_input_v1')
    extension_render_subcomponent_tertiary_input_owner_fixed = (HasToken 'widget_extension_render_subcomponent_tertiary_input_owner=extension_parent_state_tertiary_marker')
    extension_render_subcomponent_tertiary_from_input_only = (HasToken 'widget_extension_render_subcomponent_tertiary_from_input_only=1')
    extension_render_subcomponent_tertiary_visible_default = (HasToken 'widget_extension_render_subcomponent_tertiary_visible=1')
    extension_render_subcomponent_tertiary_rendered_default = (HasToken 'widget_extension_render_subcomponent_tertiary_rendered=1')
    extension_render_subcomponent_tertiary_text_default = (HasToken 'widget_extension_render_subcomponent_tertiary_text=Note: idle')
    extension_render_subcomponent_tertiary_variant_default = (HasToken 'widget_extension_render_subcomponent_tertiary_variant=muted')
    extension_render_subcomponent_tertiary_parent_coexistence_state_fixed = (HasToken 'widget_extension_render_subcomponent_tertiary_parent_coexistence_state=active')
    extension_render_subcomponent_tertiary_child_dependency_none = (HasToken 'widget_extension_render_subcomponent_tertiary_child_dependency=none')
    extension_render_layout_child_order_default = (HasToken 'widget_extension_render_layout_child_order=status_chip_v1,secondary_indicator_v1')
    extension_render_subcomponent_coexistence = (HasToken 'widget_extension_render_subcomponent_coexistence=1')
    extension_render_subcomponent_coexistence_three = (HasToken 'widget_extension_render_subcomponent_coexistence_three=1')
    extension_render_primary_summary_badge_variant_default = (HasToken 'widget_extension_render_primary_summary_badge_variant=neutral')
    extension_render_layout_mode_default = (HasToken 'widget_extension_render_layout_mode=compact')
    extension_visual_card_data_shape_default = (HasToken 'widget_extension_visual_card_data_shape=card_display_v1')
    extension_visual_layout_mode_default = (HasToken 'widget_extension_visual_layout_mode=compact')
    extension_visual_parent_visibility_rule_name_fixed = (HasToken 'widget_extension_visual_parent_visibility_rule_name=parent_secondary_indicator_visibility_v1')
    extension_visual_parent_visibility_rule_owner_fixed = (HasToken 'widget_extension_visual_parent_visibility_rule_owner=extension_parent_state')
    extension_visual_parent_visibility_rule_target_fixed = (HasToken 'widget_extension_visual_parent_visibility_rule_target=secondary_indicator_v1')
    extension_visual_parent_visibility_rule_state_default = (HasToken 'widget_extension_visual_parent_visibility_rule_state=hidden')
    extension_visual_parent_ordering_rule_name_fixed = (HasToken 'widget_extension_visual_parent_ordering_rule_name=parent_subcomponent_ordering_v1')
    extension_visual_parent_ordering_rule_owner_fixed = (HasToken 'widget_extension_visual_parent_ordering_rule_owner=extension_parent_state')
    extension_visual_parent_ordering_rule_state_default = (HasToken 'widget_extension_visual_parent_ordering_rule_state=status_first')
    extension_visual_parent_ordering_child_dependency_none = (HasToken 'widget_extension_visual_parent_ordering_child_dependency=none')
    extension_visual_parent_orchestration_rule_name_fixed = (HasToken 'widget_extension_visual_parent_orchestration_rule_name=parent_emphasis_bridge_v1')
    extension_visual_parent_orchestration_rule_owner_fixed = (HasToken 'widget_extension_visual_parent_orchestration_rule_owner=extension_parent_state')
    extension_visual_parent_orchestration_rule_state_default = (HasToken 'widget_extension_visual_parent_orchestration_rule_state=inactive')
    extension_visual_parent_orchestration_child_dependency_none = (HasToken 'widget_extension_visual_parent_orchestration_child_dependency=none')
    extension_visual_layout_container_name_fixed = (HasToken 'widget_extension_visual_layout_container_name=sandbox_extension_panel')
    extension_visual_layout_container_role_fixed = (HasToken 'widget_extension_visual_layout_container_role=subcomponent_layout_surface')
    extension_visual_layout_container_owner_fixed = (HasToken 'widget_extension_visual_layout_container_owner=extension_parent_state')
    extension_visual_layout_container_child_order_fixed = (HasToken 'widget_extension_visual_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent')
    extension_visual_layout_container_child_count_fixed = (HasToken 'widget_extension_visual_layout_container_child_count=3')
    extension_visual_layout_header_name_fixed = (HasToken 'widget_extension_visual_layout_container_header_band_name=sandbox_extension_header_band')
    extension_visual_layout_header_role_fixed = (HasToken 'widget_extension_visual_layout_container_header_band_role=layout_header_region')
    extension_visual_layout_header_owner_fixed = (HasToken 'widget_extension_visual_layout_container_header_band_owner=extension_parent_state')
    extension_visual_layout_header_title_fixed = (HasToken 'widget_extension_visual_layout_container_header_band_title=Runtime Panel')
    extension_visual_layout_header_summary_default = (HasToken 'widget_extension_visual_layout_container_header_band_summary=Mode: secondary inactive')
    extension_visual_layout_header_summary_owner_fixed = (HasToken 'widget_extension_visual_layout_container_header_band_summary_owner=extension_parent_state')
    extension_visual_layout_header_summary_child_dependency_none = (HasToken 'widget_extension_visual_layout_container_header_band_summary_child_dependency=none')
    extension_visual_layout_region_order_fixed = (HasToken 'widget_extension_visual_layout_container_region_order=header_band,body_region,footer_strip')
    extension_visual_layout_body_name_fixed = (HasToken 'widget_extension_visual_layout_container_body_region_name=sandbox_extension_body_region')
    extension_visual_layout_body_role_fixed = (HasToken 'widget_extension_visual_layout_container_body_region_role=layout_body_region')
    extension_visual_layout_body_owner_fixed = (HasToken 'widget_extension_visual_layout_container_body_region_owner=extension_parent_state')
    extension_visual_layout_body_title_fixed = (HasToken 'widget_extension_visual_layout_container_body_region_title=State Overview')
    extension_visual_layout_body_child_order_fixed = (HasToken 'widget_extension_visual_layout_container_body_region_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent')
    extension_visual_layout_body_child_count_fixed = (HasToken 'widget_extension_visual_layout_container_body_region_child_count=3')
    extension_visual_layout_body_child_dependency_none = (HasToken 'widget_extension_visual_layout_container_body_region_child_dependency=none')
    extension_visual_layout_footer_name_fixed = (HasToken 'widget_extension_visual_layout_container_footer_strip_name=sandbox_extension_footer_strip')
    extension_visual_layout_footer_role_fixed = (HasToken 'widget_extension_visual_layout_container_footer_strip_role=layout_footer_region')
    extension_visual_layout_footer_owner_fixed = (HasToken 'widget_extension_visual_layout_container_footer_strip_owner=extension_parent_state')
    extension_visual_layout_footer_title_fixed = (HasToken 'widget_extension_visual_layout_container_footer_strip_title=Next Action')
    extension_visual_layout_footer_value_fixed = (HasToken 'widget_extension_visual_layout_container_footer_strip_value=Next action: ready')
    extension_visual_layout_footer_status_owner_fixed = (HasToken 'widget_extension_visual_layout_container_footer_strip_status_owner=extension_parent_state')
    extension_visual_layout_footer_child_dependency_none = (HasToken 'widget_extension_visual_layout_container_footer_strip_child_dependency=none')
    extension_visual_layout_region_backgrounds_fixed = (HasToken 'widget_extension_visual_layout_container_region_backgrounds=header:0.10,0.12,0.14,1.00|body:0.11,0.13,0.15,1.00|footer:0.10,0.12,0.14,1.00')
    extension_visual_header_integration_profile_fixed = (HasToken 'widget_extension_visual_layout_container_header_integration_profile=panel_header_blend_v1')
    extension_visual_header_padding_refinement_fixed = (HasToken 'widget_extension_visual_layout_container_header_padding_refinement=inner:9,5,9,4')
    extension_visual_header_text_legibility_fixed = (HasToken 'widget_extension_visual_layout_container_header_text_legibility=title:17|summary:15')
    extension_visual_full_panel_cohesion_profile_fixed = (HasToken 'widget_extension_visual_layout_container_full_panel_cohesion_profile=unified_compact_surface_v1')
    extension_visual_divider_language_fixed = (HasToken 'widget_extension_visual_layout_container_divider_language=unified_control_card_surface_v1')
    extension_visual_region_spacing_rhythm_fixed = (HasToken 'widget_extension_visual_layout_container_region_spacing_rhythm=header:11|body:11|footer:11')
    extension_visual_controls_integration_profile_fixed = (HasToken 'widget_extension_visual_layout_container_controls_integration_profile=panel_controls_action_focus_v1')
    extension_visual_controls_surface_fixed = (HasToken 'widget_extension_visual_layout_container_controls_surface=bg:0.12,0.16,0.19,1.00|label:0.12,0.16,0.19,1.00')
    extension_visual_controls_spacing_fixed = (HasToken 'widget_extension_visual_layout_container_controls_spacing=label:22|input:42|row:66')
    extension_visual_controls_padding_refinement_fixed = (HasToken 'widget_extension_visual_layout_container_controls_padding_refinement=row:6')
    extension_visual_footer_integration_profile_fixed = (HasToken 'widget_extension_visual_layout_container_footer_integration_profile=panel_footer_blend_v1')
    extension_visual_footer_padding_refinement_fixed = (HasToken 'widget_extension_visual_layout_container_footer_padding_refinement=inner:9,4,9,4')
    extension_visual_footer_text_legibility_fixed = (HasToken 'widget_extension_visual_layout_container_footer_text_legibility=title:13|value:16')
    extension_visual_readability_profile_fixed = (HasToken 'widget_extension_visual_layout_container_readability_profile=panel_calm_control_card_reconstruction_v1')
    extension_visual_readability_spacing_fixed = (HasToken 'widget_extension_visual_layout_container_readability_spacing=panel:11|header:12|body:11|footer:11')
    extension_visual_readability_typography_fixed = (HasToken 'widget_extension_visual_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22')
    extension_visual_text_contrast_profile_fixed = (HasToken 'widget_extension_visual_layout_container_text_contrast_profile=calm_control_card_hierarchy_v1')
    extension_visual_primary_summary_default = (HasToken 'widget_extension_visual_primary_summary_text=State summary: inactive')
    extension_visual_primary_detail_default = (HasToken 'widget_extension_visual_primary_detail_text=Action: waiting for toggle')
    extension_visual_primary_summary_badge_variant_default = (HasToken 'widget_extension_visual_primary_summary_badge_variant=neutral')
    extension_visual_subcomponent_visible_default = (HasToken 'widget_extension_visual_subcomponent_visible=1')
    extension_visual_subcomponent_input_record_fixed = (HasToken 'widget_extension_visual_subcomponent_input_record=status_chip_input_v1')
    extension_visual_subcomponent_input_owner_fixed = (HasToken 'widget_extension_visual_subcomponent_input_owner=extension_parent_state')
    extension_visual_subcomponent_text_default = (HasToken 'widget_extension_visual_subcomponent_text=System state: ready')
    extension_visual_subcomponent_content_extra_line_default = (HasToken 'widget_extension_visual_subcomponent_content_extra_line=Feedback: ready')
    extension_visual_subcomponent_variant_default = (HasToken 'widget_extension_visual_subcomponent_variant=neutral')
    extension_visual_subcomponent_presentation_variant_default = (HasToken 'widget_extension_visual_subcomponent_presentation_variant=base')
    extension_visual_subcomponent_layout_variant_default = (HasToken 'widget_extension_visual_subcomponent_layout_variant=compact')
    extension_visual_subcomponent_layout_height_default = (HasToken 'widget_extension_visual_subcomponent_layout_height=20')
    extension_visual_subcomponent_interaction_boundary_state_default = (HasToken 'widget_extension_visual_subcomponent_interaction_boundary_state=inactive')
    extension_visual_subcomponent_parent_orchestration_state_default = (HasToken 'widget_extension_visual_subcomponent_parent_orchestration_state=inactive')
    extension_visual_subcomponent_secondary_input_record_fixed = (HasToken 'widget_extension_visual_subcomponent_secondary_input_record=secondary_indicator_input_v1')
    extension_visual_subcomponent_secondary_input_owner_fixed = (HasToken 'widget_extension_visual_subcomponent_secondary_input_owner=extension_parent_state_secondary_indicator')
    extension_visual_subcomponent_secondary_visible_default = (HasToken 'widget_extension_visual_subcomponent_secondary_visible=0')
    extension_visual_subcomponent_secondary_visibility_owner_fixed = (HasToken 'widget_extension_visual_subcomponent_secondary_visibility_owner=extension_parent_state')
    extension_visual_subcomponent_secondary_text_default = (HasToken 'widget_extension_visual_subcomponent_secondary_text=Support line: inactive')
    extension_visual_subcomponent_secondary_variant_default = (HasToken 'widget_extension_visual_subcomponent_secondary_variant=neutral')
    extension_visual_subcomponent_secondary_parent_orchestration_state_default = (HasToken 'widget_extension_visual_subcomponent_secondary_parent_orchestration_state=inactive')
    extension_visual_subcomponent_tertiary_input_record_fixed = (HasToken 'widget_extension_visual_subcomponent_tertiary_input_record=tertiary_marker_input_v1')
    extension_visual_subcomponent_tertiary_input_owner_fixed = (HasToken 'widget_extension_visual_subcomponent_tertiary_input_owner=extension_parent_state_tertiary_marker')
    extension_visual_subcomponent_tertiary_visible_default = (HasToken 'widget_extension_visual_subcomponent_tertiary_visible=1')
    extension_visual_subcomponent_tertiary_text_default = (HasToken 'widget_extension_visual_subcomponent_tertiary_text=Note: idle')
    extension_visual_subcomponent_tertiary_variant_default = (HasToken 'widget_extension_visual_subcomponent_tertiary_variant=muted')
    extension_visual_subcomponent_tertiary_parent_coexistence_state_fixed = (HasToken 'widget_extension_visual_subcomponent_tertiary_parent_coexistence_state=active')
    extension_visual_subcomponent_tertiary_child_dependency_none = (HasToken 'widget_extension_visual_subcomponent_tertiary_child_dependency=none')
    extension_visual_layout_child_order_default = (HasToken 'widget_extension_visual_layout_child_order=status_chip_v1,secondary_indicator_v1')
    extension_visual_subcomponent_coexistence = (HasToken 'widget_extension_visual_subcomponent_coexistence=1')
    extension_visual_subcomponent_coexistence_three = (HasToken 'widget_extension_visual_subcomponent_coexistence_three=1')
    extension_info_card_visible = (HasToken 'widget_extension_visual_info_card_visible=1')
    extension_secondary_placeholder_present = (HasToken 'widget_extension_secondary_placeholder_present=1')
    extension_secondary_placeholder_text_fixed = (HasToken 'widget_extension_secondary_placeholder_text=State summary: inactive')
    extension_secondary_placeholder_state_default = (HasToken 'widget_extension_secondary_placeholder_state=inactive')
    extension_placeholder_inert = (HasToken 'widget_extension_placeholder_visible=1')
    extension_layout_background_present = (HasToken 'widget_extension_visual_bounds_background=')
    extension_layout_label_present = (HasToken 'widget_extension_visual_bounds_label=')
    extension_layout_placeholder_present = (HasToken 'widget_extension_visual_bounds_placeholder=')
    extension_layout_info_card_present = (HasToken 'widget_extension_visual_bounds_info_card=')
    extension_layout_status_chip_present = (HasToken 'widget_extension_visual_bounds_status_chip=')
    extension_layout_secondary_indicator_present = (HasToken 'widget_extension_visual_bounds_secondary_indicator=')
    extension_layout_tertiary_marker_present = (HasToken 'widget_extension_visual_bounds_tertiary_marker=')
    extension_layout_container_bounds_present = (HasToken 'widget_extension_visual_bounds_layout_container=')
    extension_layout_header_bounds_present = (HasToken 'widget_extension_visual_bounds_layout_header_band=')
    extension_layout_body_bounds_present = (HasToken 'widget_extension_visual_bounds_layout_body_region=')
    extension_layout_footer_bounds_present = (HasToken 'widget_extension_visual_bounds_layout_footer_strip=')
    extension_layout_child_order_default = (HasToken 'widget_extension_layout_child_order=status_chip_v1,secondary_indicator_v1')
    extension_visual_background_present = (HasToken 'widget_extension_visual_contract_background_present=1')
    extension_visual_label_present = (HasToken 'widget_extension_visual_contract_label_present=1')
    extension_visual_info_card_present = (HasToken 'widget_extension_visual_contract_info_card_visible=1')
    extension_visual_secondary_placeholder_present = (HasToken 'widget_extension_visual_contract_secondary_placeholder_visible=1')
    extension_visual_capture_completed = (HasToken 'widget_extension_visual_capture_done=1')
    sandbox_clean_exit = (($exitCode -eq 0) -and (HasToken 'widget_sandbox_exit=0'))
    first_frame = (HasToken 'widget_first_frame=1')
  }

  $pass = $true
  foreach ($entry in $checks.GetEnumerator()) {
    if (-not [bool]$entry.Value) {
      $pass = $false
      break
    }
  }

  @(
    'PHASE 40.38 extension visual contract',
    "timestamp=$(Get-Date -Format o)",
    "widget_exe=$widgetExe",
    'mode=--extension-visual-baseline + --sandbox-extension + NGK_WIDGET_EXTENSION_VISUAL_BASELINE=1',
    "render_artifact_log=$logPath",
    "gate=$(if ($pass) { 'PASS' } else { 'FAIL' })",
    '--- checks ---'
  ) + ($checks.GetEnumerator() | ForEach-Object { "$_" }) | Set-Content -Path $reportPath -Encoding UTF8

  if (-not $pass) {
    Write-Output 'extension_visual_contract=FAIL'
    exit 1
  }

  Write-Output 'extension_visual_contract=PASS'
  Write-Output "report=$reportPath"
  exit 0
}
finally {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
  $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  $env:NGK_WIDGET_VISUAL_BASELINE = $oldVisual
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = $oldExtVisual
  $env:NGK_WIDGET_SANDBOX_LANE = $oldLane
}









