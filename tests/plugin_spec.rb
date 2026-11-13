# frozen_string_literal: true

require 'json'

# Tests for the plugin, run with `trmnlp test`. Add `--report Debug/test-report` for a page of every screen drawn.
# Docs: https://github.com/usetrmnl/trmnlp/blob/main/docs/testing.md
#
# The fixtures are real EVO API answers recorded on 13 Nov 2026 at 12:15 CET:
#   at_* - EVO Bruno-Marek-Allee (Austria): two finished slots, the running one, three forecast slots
#   de_* - EVO Alexanderplatz (Germany): slot values in the thousands of percent, so the chart must stay hidden
RSpec.describe 'EVO Fitness Occupancy' do
  gym_at = 'ba765872-0969-4eeb-9a24-5384d78c97b1'
  gym_de = '13cbafa0-8b29-4aa8-bed7-34e972caa165'
  screens = TRMNLP::Testing::PUBLISHABLE_RECIPE_SCREENS
  views = TRMNLP::Testing::PUBLISHABLE_RECIPE_VIEWS

  def fixture(name) = JSON.parse(File.read(File.join(__dir__, 'fixtures', "#{name}.json")))

  # The three polling URLs: live count, today's slots and tomorrow's forecast. Any gym id matches,
  # so every option of the gym fields draws with the same data.
  def evo_mocks(country, current: fixture("#{country}_current"))
    {
      %r{/api/v1/locations/[^/]*/current\z} => { json: current },
      %r{/api/v1/locations/[^/]*/timeline\z} => { json: fixture("#{country}_timeline_today") },
      %r{/api/v1/locations/[^/]*/timeline\?date=} => { json: fixture("#{country}_timeline_tomorrow") }
    }
  end

  let(:now) { '2026-11-13T12:15:00+01:00' }
  let(:mocks) { evo_mocks('at') }
  let(:custom_fields) { { 'country' => 'at', 'gym_at' => gym_at, 'gym_de' => '', 'gym_ch' => '', 'language' => 'de' } }

  # Every view on TRMNL's devices, a failing API and every select option: page errors, leaked values,
  # overlapping text, dark mode.
  it_behaves_like 'a publishable recipe'

  describe 'an Austrian gym' do
    views.product(screens).each do |view, screen|
      it "fits the #{view} view on #{TRMNLP::Testing.screen_name(screen)}" do
        expect(trmnl.render(view:, **screen, mocks:, custom_fields:, now:)).to have_no_overflow
      end
    end

    it 'shows the live count, the chart and the quietest slot ahead' do
      screen = trmnl.render(mocks:, custom_fields:, now:)
      expect(screen).to have_text('17 / 80 Personen')
      expect(screen).to have_text('jetzt')
      expect(screen).to have_text('Am ruhigsten')
      expect(screen).to have_text('Morgen · Prognose')
      expect(screen).to have_css('.outline', count: 12)
    end

    it 'shows the time slots with "Uhr" in German and "h" in English and French' do
      expect(trmnl.render(mocks:, custom_fields:, now:)).to have_text('20–24 Uhr')
      expect(trmnl.render(mocks:, custom_fields: custom_fields.merge('language' => 'en'), now:))
        .to have_text('Quietest').and(have_text('20–24 h'))
      expect(trmnl.render(mocks:, custom_fields: custom_fields.merge('language' => 'fr'), now:))
        .to have_text('Le plus calme').and(have_text('20–24 h'))
    end
  end

  describe 'a German gym' do
    let(:mocks) { evo_mocks('de') }
    let(:custom_fields) { super().merge('country' => 'de', 'gym_at' => '', 'gym_de' => gym_de) }

    it 'shows the live count and hides the chart' do
      screen = trmnl.render(mocks:, custom_fields:, now:)
      expect(screen).to have_text('Für dieses Studio gibt es keine Zeitfenster-Daten')
      expect(screen).to have_no_css('.outline')
    end

    views.product(screens).each do |view, screen|
      it "fits the #{view} view on #{TRMNLP::Testing.screen_name(screen)}" do
        expect(trmnl.render(view:, **screen, mocks:, custom_fields:, now:)).to have_no_overflow
      end
    end
  end

  describe 'a full gym' do
    let(:mocks) { evo_mocks('at', current: fixture('at_current').merge('current' => 80, 'percentageUsed' => 100)) }

    views.product(screens).each do |view, screen|
      it "fits 100% in the #{view} view on #{TRMNLP::Testing.screen_name(screen)}" do
        expect(trmnl.render(view:, **screen, mocks:, custom_fields:, now:))
          .to have_text('100%').and(have_no_overflow).and(have_no_overlapping_text)
      end
    end
  end

  describe 'no gym selected' do
    let(:custom_fields) { super().merge('gym_at' => '') }
    # The real API answers 404 for a missing gym id.
    let(:mocks) { { '*' => { status: 404, body: 'Not Found' } } }

    views.each do |view|
      it "asks for a gym in the #{view} view" do
        expect(trmnl.render(view:, mocks:, custom_fields:, now:)).to have_text('Studio auswählen')
      end
    end
  end
end
