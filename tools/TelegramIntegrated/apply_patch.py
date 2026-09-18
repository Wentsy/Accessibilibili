from pathlib import Path

ROOT = Path(r"__TELEGRAM_ROOT__")

def replace_once(path, old, new):
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Pattern not found in {path}")
    if text.count(old) != 1:
        raise SystemExit(f"Pattern occurs {text.count(old)} times in {path}, expected 1")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"patched {path}")

# 1) Under screen-reader mode Tab must remain focus navigation.
replace_once(
    Path("Telegram/SourceFiles/chat_helpers/field_autocomplete.cpp"),
    '#include "ui/round_rect.h"\n#include "ui/ui_utility.h"',
    '#include "ui/round_rect.h"\n#include "ui/screen_reader_mode.h"\n#include "ui/ui_utility.h"',
)

replace_once(
    Path("Telegram/SourceFiles/chat_helpers/field_autocomplete.cpp"),
    '''field->tabbed(
	) | rpl::on_next([=](not_null<Ui::InputField::TabbedRequest*> request) {
		if (!raw->isHidden()) {
			raw->chooseSelected(FieldAutocomplete::ChooseMethod::ByTab);
			request->handled = true;
		}
	}, raw->lifetime());''',
    '''field->tabbed(
	) | rpl::on_next([=](not_null<Ui::InputField::TabbedRequest*> request) {
		// Screen-reader users need Tab to move focus out of the composer.
		// In stock Telegram this handler consumes the first Tab while bot
		// commands (for example /help) are visible, which makes the message
		// list require a second Tab press.
		if (Ui::ScreenReaderModeActive()) {
			return;
		}
		if (!raw->isHidden()) {
			raw->chooseSelected(FieldAutocomplete::ChooseMethod::ByTab);
			request->handled = true;
		}
	}, raw->lifetime());''',
)

# 2) Legacy/main history widget: composer -> message list in one Tab.
replace_once(
    Path("Telegram/SourceFiles/history/history_widget.cpp"),
    '''_field->tabbed(
	) | rpl::on_next([=](not_null<Ui::InputField::TabbedRequest*> request) {
		if (_supportAutocomplete) {
			_supportAutocomplete->activate(_field.data());
			request->handled = true;
		}
	}, _field->lifetime());''',
    '''_field->tabbed(
	) | rpl::on_next([=](not_null<Ui::InputField::TabbedRequest*> request) {
		if (Ui::ScreenReaderModeActive() && !request->backward && _list) {
			// Accessibility-first focus order:
			// message composer -> message list.
			_list->setFocus();
			request->handled = true;
			return;
		}
		if (_supportAutocomplete) {
			_supportAutocomplete->activate(_field.data());
			request->handled = true;
		}
	}, _field->lifetime());''',
)

# 3) Newer ChatWidget path: same one-Tab rule.
replace_once(
    Path("Telegram/SourceFiles/history/view/history_view_chat_section.cpp"),
    '''	if (session().supportMode() && mode() == Mode::History && !_topic) {
		_supportAutocomplete = std::make_unique<Support::Autocomplete>(
			this,
			&session());
		supportInitAutocomplete();
		_composeControls->fieldTabbed(
		) | rpl::on_next([=](
				not_null<Ui::InputField::TabbedRequest*> request) {
			if (_supportAutocomplete) {
				if (const auto field = _composeControls->fieldForMention()) {
					_supportAutocomplete->activate(field);
					request->handled = true;
				}
			}
		}, lifetime());
	}''',
    '''	_composeControls->fieldTabbed(
	) | rpl::on_next([=](
			not_null<Ui::InputField::TabbedRequest*> request) {
		if (Ui::ScreenReaderModeActive() && !request->backward && _inner) {
			// Accessibility-first focus order:
			// message composer -> message list.
			_inner->setFocus();
			request->handled = true;
		}
	}, lifetime());

	if (session().supportMode() && mode() == Mode::History && !_topic) {
		_supportAutocomplete = std::make_unique<Support::Autocomplete>(
			this,
			&session());
		supportInitAutocomplete();
		_composeControls->fieldTabbed(
		) | rpl::on_next([=](
				not_null<Ui::InputField::TabbedRequest*> request) {
			if (!request->handled && _supportAutocomplete) {
				if (const auto field = _composeControls->fieldForMention()) {
					_supportAutocomplete->activate(field);
					request->handled = true;
				}
			}
		}, lifetime());
	}''',
)

print("All Telegram accessibility patches applied.")
