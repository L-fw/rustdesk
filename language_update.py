import os
import re

lang_dir = r'd:\git_rustdesk\rustdesk\src\lang'

translations = {
    'bg': {
        'title': 'Моля, потвърдете самоличността на другата страна.',
        'text1': 'Ако другата страна не е служител на Gamwing Global Technology Co., Ltd. и ви моли да използвате Gamwing и да стартирате услугата, не продължавайте и затворете незабавно.'
    },
    'ca': {
        'title': "Si us plau, verifiqueu la identitat de l'altra part.",
        'text1': "Si l'altra part no és personal de Gamwing Global Technology Co., Ltd. i us demana que utilitzeu Gamwing i inicieu el servei, no continueu i pengeu immediatament."
    },
    'cs': {
        'title': 'Ověřte prosím totožnost druhé strany.',
        'text1': 'Pokud druhá strana není zaměstnancem Gamwing Global Technology Co., Ltd. a žádá vás o použití Gamwing a spuštění služby, nepokračujte a okamžitě zavěste.'
    },
    'da': {
        'title': 'Bekræft venligst den anden parts identitet.',
        'text1': 'Hvis den anden part ikke er personale fra Gamwing Global Technology Co., Ltd. og beder dig om at bruge Gamwing og starte tjenesten, skal du ikke fortsætte og lægge på med det samme.'
    },
    'de': {
        'title': 'Bitte überprüfen Sie die Identität der anderen Partei.',
        'text1': 'Wenn die andere Partei kein Mitarbeiter von Gamwing Global Technology Co., Ltd. ist und Sie bittet, Gamwing zu verwenden und den Dienst zu starten, fahren Sie nicht fort und legen Sie sofort auf.'
    },
    'el': {
        'title': 'Παρακαλούμε επιβεβαιώστε την ταυτότητα του άλλου μέρους.',
        'text1': 'Εάν το άλλο μέρος δεν είναι προσωπικό της Gamwing Global Technology Co., Ltd. και σας ζητήσει να χρησιμοποιήσετε το Gamwing και να ξεκινήσετε την υπηρεσία, μην συνεχίσετε και κλείστε αμέσως.'
    },
    'eo': {
        'title': 'Bonvolu kontroli la identecon de la alia partio.',
        'text1': 'Se la alia partio ne estas personaro de Gamwing Global Technology Co., Ltd. kaj petas vin uzi Gamwing kaj lanĉi la servon, ne daŭrigu kaj tuj interrompu la komunikadon.'
    },
    'es': {
        'title': 'Por favor, verifique la identidad de la otra parte.',
        'text1': 'Si la otra parte no es personal de Gamwing Global Technology Co., Ltd. y le pide que use Gamwing e inicie el servicio, no proceda y cuelgue de inmediato.'
    },
    'et': {
        'title': 'Palun kontrollige teise osapoole isikusamasust.',
        'text1': 'Kui teine osapool ei ole Gamwing Global Technology Co., Ltd. töötaja ja palub teil kasutada Gamwingi ning käivitada teenus, ärge jätkake ja lõpetage kohe kõne.'
    },
    'eu': {
        'title': 'Mesedez, egiaztatu beste alderdiaren identitatea.',
        'text1': 'Beste alderdia ez bada Gamwing Global Technology Co., Ltd.-ko langilea eta Gamwing erabili eta zerbitzua hastea eskatzen badizu, ez jarraitu eta zintzilikatu berehala.'
    },
    'fa': {
        'title': 'لطفاً هویت طرف مقابل را تأیید کنید.',
        'text1': 'اگر طرف مقابل از کارکنان Gamwing Global Technology Co., Ltd. نیست و از شما می‌خواهد از Gamwing استفاده کنید و سرویس را شروع کنید، ادامه ندهید و فوراً تماس را قطع کنید.'
    },
    'fi': {
        'title': 'Vahvista toisen osapuolen henkilöllisyys.',
        'text1': 'Jos toinen osapuoli ei ole Gamwing Global Technology Co., Ltd. -henkilöstöä ja pyytää sinua käyttämään Gamwingiä ja käynnistämään palvelun, älä jatka vaan katkaise puhelu heti.'
    },
    'fr': {
        'title': "Veuillez vérifier l'identité de l'autre partie.",
        'text1': "Si l'autre partie n'appartient pas au personnel de Gamwing Global Technology Co., Ltd. et vous demande d'utiliser Gamwing et de démarrer le service, ne continuez pas et raccrochez immédiatement."
    },
    'ge': {
        'title': 'გთხოვთ დაადასტუროთ მეორე მხარის ვინაობა.',
        'text1': 'თუ მეორე მხარე არ არის Gamwing Global Technology Co., Ltd.-ის თანამშრომელი და გთხოვთ გამოიყენოთ Gamwing და ჩართოთ სერვისი, არ გააგრძელოთ და დაუყოვნებლივ გათიშეთ.'
    },
    'he': {
        'title': 'אנא ודא את זהות הצד השני.',
        'text1': 'אם הצד השני אינו צוות Gamwing Global Technology Co., Ltd. ומבקש ממך להשתמש ב-Gamwing ולהפעיל את השירות, אל תמשיך ונתק מיד.'
    },
    'hr': {
        'title': 'Molimo potvrdite identitet druge strane.',
        'text1': 'Ako druga strana nije osoblje Gamwing Global Technology Co., Ltd. i traži od vas da koristite Gamwing i pokrenete uslugu, nemojte nastaviti i odmah prekinite vezu.'
    },
    'hu': {
        'title': 'Kérjük, ellenőrizze a másik fél személyazonosságát.',
        'text1': 'Ha a másik fél nem a Gamwing Global Technology Co., Ltd. munkatársa, és arra kéri, hogy használja a Gamwing-ot és indítsa el a szolgáltatást, ne folytassa, és azonnal bontsa a vonalat.'
    },
    'id': {
        'title': 'Harap verifikasi identitas pihak lain.',
        'text1': 'Jika pihak lain bukan staf Gamwing Global Technology Co., Ltd. dan meminta Anda untuk menggunakan Gamwing dan memulai layanan, jangan lanjutkan dan segera tutup telepon.'
    },
    'it': {
        'title': "Si prega di verificare l'identità dell'altra parte.",
        'text1': "Se l'altra parte non è personale di Gamwing Global Technology Co., Ltd. e ti chiede di utilizzare Gamwing e avviare il servizio, non procedere e riaggancia immediatamente."
    },
    'ja': {
        'title': '相手の身元を確認してください。',
        'text1': '相手が Gamwing Global Technology Co., Ltd. のスタッフではなく、Gamwing を使用してサービスを開始するように求めてきた場合は、続行せずにすぐに電話を切ってください。'
    },
    'ko': {
        'title': '상대방의 신원을 확인해 주세요.',
        'text1': '상대방이 Gamwing Global Technology Co., Ltd. 직원이 아닌데 Gamwing을 사용하여 서비스를 시작할 것을 요구한다면, 진행하지 말고 즉시 전화를 끊으세요.'
    },
    'kz': {
        'title': 'Екінші тараптың жеке басын растаңыз.',
        'text1': 'Егер екінші тарап Gamwing Global Technology Co., Ltd. қызметкері болмаса және сізден Gamwing қолдануды және қызметті бастауды сұраса, жалғастырмаңыз және телефонды дереу қойыңыз.'
    },
    'lt': {
        'title': 'Prašome patikrinti kitos šalies tapatybę.',
        'text1': 'Jei kita šalis nėra Gamwing Global Technology Co., Ltd. darbuotojas ir prašo jūsų naudoti Gamwing bei paleisti paslaugą, netęskite ir nedelsdami padėkite ragelį.'
    },
    'lv': {
        'title': 'Lūdzu, pārbaudiet otras puses identitāti.',
        'text1': 'Ja otra puse nav Gamwing Global Technology Co., Ltd. darbinieks un lūdz jūs izmantot Gamwing un sākt pakalpojumu, neturpiniet un nekavējoties nolieciet klausuli.'
    },
    'nb': {
        'title': 'Vennligst bekreft den andre partens identitet.',
        'text1': 'Hvis den andre parten ikke er personale fra Gamwing Global Technology Co., Ltd. og ber deg om å bruke Gamwing og starte tjenesten, må du ikke fortsette og legge på umiddelbart.'
    },
    'nl': {
        'title': 'Controleer de identiteit van de andere partij.',
        'text1': 'Als de andere partij geen personeel is van Gamwing Global Technology Co., Ltd. en u vraagt om Gamwing te gebruiken en de service te starten, ga dan niet verder en hang onmiddellijk op.'
    },
    'pl': {
        'title': 'Proszę zweryfikować tożsamość drugiej strony.',
        'text1': 'Jeśli druga strona nie jest personelem Gamwing Global Technology Co., Ltd. i prosi Cię o użycie Gamwing i uruchomienie usługi, nie kontynuuj i natychmiast się rozłącz.'
    },
    'pt_PT': {
        'title': 'Por favor, verifique a identidade da outra parte.',
        'text1': 'Se a outra parte não for funcionário da Gamwing Global Technology Co., Ltd. e solicitar que você use o Gamwing e inicie o serviço, não prossiga e desligue imediatamente.'
    },
    'ptbr': {
        'title': 'Por favor, verifique a identidade da outra parte.',
        'text1': 'Se a outra parte não for funcionário da Gamwing Global Technology Co., Ltd. e pedir para você usar o Gamwing e iniciar o serviço, não prossiga e desligue imediatamente.'
    },
    'ro': {
        'title': 'Vă rugăm să verificați identitatea celeilalte părți.',
        'text1': 'Dacă cealaltă parte nu este personal Gamwing Global Technology Co., Ltd. și vă cere să utilizați Gamwing și să începeți serviciul, nu continuați și închideți imediat.'
    },
    'ru': {
        'title': 'Пожалуйста, проверьте личность собеседника.',
        'text1': 'Если собеседник не является сотрудником Gamwing Global Technology Co., Ltd. и просит вас использовать Gamwing и запустить службу, не продолжайте и немедленно повесьте трубку.'
    },
    'sc': {
        'title': "Verìfica s'identidade de s'àtera persone.",
        'text1': "Si s'àtera persone no est un'impiegadu de Gamwing Global Technology Co., Ltd. e ti pedit de impreare Gamwing e de allùghere su servìtziu, no l'iscurtes e tanca sa mutida luegus."
    },
    'sk': {
        'title': 'Overte prosím totožnosť druhej strany.',
        'text1': 'Ak druhá strana nie je zamestnancom Gamwing Global Technology Co., Ltd. a žiada vás o použitie Gamwing a spustenie služby, nepokračujte a okamžite zaveste.'
    },
    'sl': {
        'title': 'Prosimo, preverite identiteto druge osebe.',
        'text1': 'Če druga oseba ni uslužbenec Gamwing Global Technology Co., Ltd. in od vas zahteva, da uporabite Gamwing in zaženete storitev, ne nadaljujte in takoj prekinite.'
    },
    'sq': {
        'title': 'Ju lutemi verifikoni identitetin e palës tjetër.',
        'text1': 'Nëse pala tjetër nuk është staf i Gamwing Global Technology Co., Ltd. dhe ju kërkon të përdorni Gamwing dhe të nisni shërbimin, mos vazhdoni dhe mbyllni lidhjen menjëherë.'
    },
    'sr': {
        'title': 'Молимо потврдите идентитет друге стране.',
        'text1': 'Ако друга страна није особље Gamwing Global Technology Co., Ltd. и тражи од вас да користите Gamwing и покренете услугу, немојте наставити и одмах прекините везу.'
    },
    'sv': {
        'title': 'Vänligen verifiera motpartens identitet.',
        'text1': 'Om den andra parten inte är personal från Gamwing Global Technology Co., Ltd. och ber dig att använda Gamwing och starta tjänsten, fortsätt inte och lägg på omedelbart.'
    },
    'ta': {
        'title': 'தயவுசெய்து மற்ற நபரின் அடையாளத்தை சரிபார்க்கவும்.',
        'text1': 'மற்ற நபர் Gamwing Global Technology Co., Ltd. பணியாளர் இல்லை மற்றும் Gamwing பயன்படுத்தி சேவையை தொடங்க சொன்னால், தொடர வேண்டாம் மற்றும் உடனடியாக இணைப்பை துண்டிக்கவும்.'
    },
    'template': {
        'title': 'Please verify the identity of the other party.',
        'text1': 'If the other party is not Gamwing Global Technology Co., Ltd. staff and asks you to use Gamwing and start the service, do not proceed and hang up immediately.'
    },
    'th': {
        'title': 'โปรดตรวจสอบตัวตนของอีกฝ่าย',
        'text1': 'หากอีกฝ่ายไม่ใช่เจ้าหน้าที่ของ Gamwing Global Technology Co., Ltd. และขอให้คุณใช้ Gamwing และเริ่มบริการ โปรดอย่าดำเนินการต่อและวางสายทันที'
    },
    'tr': {
        'title': 'Lütfen diğer tarafın kimliğini doğrulayın.',
        'text1': "Diğer taraf Gamwing Global Technology Co., Ltd. personeli değilse ve Gamwing'i kullanıp hizmeti başlatmanızı isterse, devam etmeyin ve derhal telefonu kapatın."
    },
    'tw': {
        'title': '請確認對方的身分。',
        'text1': '如果對方不是佳影寰球科技有限公司的工作人員，卻要求你使用 Gamwing 啟動服務，請勿繼續操作並立刻掛斷。'
    },
    'uk': {
        'title': 'Будь ласка, перевірте особу співрозмовника.',
        'text1': 'Якщо співрозмовник не є співробітником Gamwing Global Technology Co., Ltd. і просить вас використати Gamwing та запустити службу, не продовжуйте і негайно покладіть слухавку.'
    },
    'vi': {
        'title': 'Vui lòng xác minh danh tính của đầu dây bên kia.',
        'text1': 'Nếu đầu dây bên kia không phải là nhân viên Gamwing Global Technology Co., Ltd. và yêu cầu bạn sử dụng Gamwing và bắt đầu dịch vụ, không tiếp tục và cúp máy ngay lập tức.'
    }
}

for lang, data in translations.items():
    file_path = os.path.join(lang_dir, f'{lang}.rs')
    if os.path.exists(file_path):
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        for i, line in enumerate(lines):
            if '(\"scam_title\",' in line:
                lines[i] = f'        (\"scam_title\", \"{data["title"]}\"),\n'
            elif '(\"scam_text1\",' in line:
                lines[i] = f'        (\"scam_text1\", \"{data["text1"]}\"),\n'

        with open(file_path, 'w', encoding='utf-8') as f:
            f.writelines(lines)
        print(f'Updated {lang}')