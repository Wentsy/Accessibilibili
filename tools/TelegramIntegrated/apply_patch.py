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


# 4) F6 toggles focus between the message list and the composer.
# Keep this local to the chat widget and only active for screen-reader mode.
replace_once(
    Path("Telegram/SourceFiles/history/history_widget.cpp"),
    '''#include <QtGui/QWindow>
#include <QtCore/QMimeData>''',
    '''#include <QtGui/QWindow>
#include <QtCore/QMimeData>
#include <QShortcut>''',
)

replace_once(
    Path("Telegram/SourceFiles/history/history_widget.cpp"),
    '''	setAcceptDrops(true);
	setVisualTabOrder(true);

	// The controls inside these are created in an order of their own''',
    '''	setAcceptDrops(true);
	setVisualTabOrder(true);

	const auto accessibilityFocusShortcut = new QShortcut(
		QKeySequence(Qt::Key_F6),
		this);
	accessibilityFocusShortcut->setContext(Qt::WidgetWithChildrenShortcut);
	accessibilityFocusShortcut->setAutoRepeat(false);
	QObject::connect(
		accessibilityFocusShortcut,
		&QShortcut::activated,
		this,
		[=] {
			if (!Ui::ScreenReaderModeActive() || !_list) {
				return;
			}
			if (_list->hasFocus()) {
				_field->setFocus();
			} else {
				_list->setFocus();
			}
		});

	// The controls inside these are created in an order of their own''',
)

replace_once(
    Path("Telegram/SourceFiles/history/view/history_view_chat_section.cpp"),
    '''#include <limits>
#include <QtCore/QMimeData>''',
    '''#include <limits>
#include <QtCore/QMimeData>
#include <QShortcut>''',
)

replace_once(
    Path("Telegram/SourceFiles/history/view/history_view_chat_section.cpp"),
    '''	setupRoot();
	setupShortcuts();

	_peer->updateFull();''',
    '''	setupRoot();
	setupShortcuts();

	const auto accessibilityFocusShortcut = new QShortcut(
		QKeySequence(Qt::Key_F6),
		this);
	accessibilityFocusShortcut->setContext(Qt::WidgetWithChildrenShortcut);
	accessibilityFocusShortcut->setAutoRepeat(false);
	QObject::connect(
		accessibilityFocusShortcut,
		&QShortcut::activated,
		this,
		[=] {
			if (!Ui::ScreenReaderModeActive() || !_inner) {
				return;
			}
			if (_inner->hasFocus()) {
				_composeControls->focus();
			} else {
				_inner->setFocus();
			}
		});

	_peer->updateFull();''',
)

# 5) Expose Bot Commands as a real accessible list without putting it back
# into Tab order. Up/Down continue to operate the existing selection logic
# while the composer keeps keyboard focus; each selection change emits an
# accessibility focus event so NVDA reads the command and description.
replace_once(
    Path("Telegram/SourceFiles/chat_helpers/field_autocomplete.cpp"),
    '''	void onParentGeometryChanged();

private:
	void paintEvent(QPaintEvent *e) override;''',
    '''	void onParentGeometryChanged();

	QAccessible::Role accessibilityRole() override {
		return QAccessible::Role::List;
	}
	std::optional<Qt::Orientation> accessibilityOrientation() const override {
		return Qt::Vertical;
	}
	int accessibilityChildCount() const override;
	QString accessibilityChildName(int index) const override;
	QAccessible::State accessibilityChildState(int index) const override;
	QAccessible::Role accessibilityChildRole() const override;
	QRect accessibilityChildRect(int index) const override;

private:
	void paintEvent(QPaintEvent *e) override;''',
)

replace_once(
    Path("Telegram/SourceFiles/chat_helpers/field_autocomplete.cpp"),
    '''bool FieldAutocomplete::Inner::commandsWithUsername() const {
	const auto botStatus = BotStatusFor(_parent->chat(), _parent->channel());
	return (botStatus != Data::BotStatus::NoBots)
		|| (_parent->filter().indexOf('@') > 0);
}

void FieldAutocomplete::Inner::updateSelectedRow() {''',
    '''bool FieldAutocomplete::Inner::commandsWithUsername() const {
	const auto botStatus = BotStatusFor(_parent->chat(), _parent->channel());
	return (botStatus != Data::BotStatus::NoBots)
		|| (_parent->filter().indexOf('@') > 0);
}

int FieldAutocomplete::Inner::accessibilityChildCount() const {
	return (!_parent->isHidden() && !_brows->empty())
		? int(_brows->size())
		: 0;
}

QString FieldAutocomplete::Inner::accessibilityChildName(int index) const {
	if (index < 0 || index >= int(_brows->size())) {
		return {};
	}
	const auto &row = _brows->at(index);
	auto command = row.command.isEmpty()
		? QString()
		: ('/' + row.command);
	if (!command.isEmpty() && commandsWithUsername()) {
		command += '@' + PrimaryUsername(row.user);
	}
	if (row.description.isEmpty()) {
		return command;
	} else if (command.isEmpty()) {
		return row.description;
	}
	return command + u", "_q + row.description;
}

QAccessible::State FieldAutocomplete::Inner::accessibilityChildState(
		int index) const {
	auto state = QAccessible::State();
	if (index < 0 || index >= int(_brows->size())) {
		return state;
	}
	state.focusable = true;
	state.selectable = true;
	if (index == _sel) {
		state.focused = true;
		state.active = true;
		state.selected = true;
	}
	return state;
}

QAccessible::Role FieldAutocomplete::Inner::accessibilityChildRole() const {
	return QAccessible::Role::ListItem;
}

QRect FieldAutocomplete::Inner::accessibilityChildRect(int index) const {
	return (index >= 0 && index < int(_brows->size()))
		? selectedRect(index)
		: QRect();
}

void FieldAutocomplete::Inner::updateSelectedRow() {''',
)

replace_once(
    Path("Telegram/SourceFiles/chat_helpers/field_autocomplete.cpp"),
    '''void FieldAutocomplete::Inner::setSel(int sel, bool scroll) {
	updateSelectedRow();
	_sel = sel;
	updateSelectedRow();

	if (scroll && _sel >= 0) {''',
    '''void FieldAutocomplete::Inner::setSel(int sel, bool scroll) {
	updateSelectedRow();
	_sel = sel;
	updateSelectedRow();

	if (Ui::ScreenReaderModeActive()
		&& !_parent->isHidden()
		&& !_brows->empty()
		&& _sel >= 0
		&& _sel < int(_brows->size())) {
		accessibilityChildFocused(_sel);
	}

	if (scroll && _sel >= 0) {''',
)

print("All Telegram accessibility patches applied.")
