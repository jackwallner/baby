#!/usr/bin/env python3
"""Apply optimized native keywords/subtitles for Posture (all fastlane locales)."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"

# Posture ASO v4 — lean indie-winnable keyword strategy
# Name indexes (free): posture, check, active, daily
# Subtitle indexes (free): neck, desk, slouch, coach
# 10 field tokens (68 chars). All H&F-relevant. Each has standalone pop>=20
# OR unlocks a phrase we can realistically rank for.
# Target phrases: posture reminder(16), daily health(21), health check(21),
#   body scan(8), posture scan(6), habit tracker(67 via compound), back care(5)
KEYWORDS: dict[str, str] = {
    "en-US": "reminder,habit,scan,health,body,back,care,spine,wellness,tracker,streak,airpods,watch,widget,fit",
    "en-GB": "reminder,habit,scan,health,body,back,care,spine,wellness,tracker,streak,airpods,watch,widget,fit",
    "en-AU": "reminder,habit,scan,health,body,back,care,spine,wellness,tracker,streak,airpods,watch,widget,fit",
    "en-CA": "reminder,habit,scan,health,body,back,care,spine,wellness,tracker,streak,airpods,watch,widget,fit",
    "de-DE": "erinnerung,gewohnheit,scan,gesundheit,körper,rücken,oase,wirbelsäule,wohlbefinden,tracker,serie,airpods,uhr,widget,fitness",
    "fr-FR": "rappel,habitude,scan,santé,corps,dos,soin,colonne,bien-être,suivi,série,airpods,montre,widget,forme",
    "fr-CA": "rappel,habitude,scan,santé,corps,dos,soin,colonne,bien-être,suivi,série,airpods,montre,widget,forme",
    "es-ES": "recordatorio,hábito,escaner,salud,cuerpo,espalda,cuidado,columna,bienestar,seguimiento,racha,airpods,reloj,widget,forma",
    "es-MX": "recordatorio,hábito,escaner,salud,cuerpo,espalda,cuidado,columna,bienestar,seguimiento,racha,airpods,reloj,widget,forma",
    "ca": "recordatori,hàbit,escaneig,salut,cos,esquena,cura,columna,benestar,seguiment,ratxa,airpods,rellotge,widget,forma",
    "it": "promemoria,abitudine,scansione,salute,corpo,schiena,cura,colonna,benessere,tracciamento,serie,airpods,orologio,widget,forma",
    "pt-BR": "lembrete,hábito,escaneamento,saúde,corpo,costas,cuidado,coluna,bem-estar,rastreamento,série,airpods,relógio,widget,forma",
    "pt-PT": "lembrete,hábito,digital,saúde,corpo,costas,cuidado,coluna,bem-estar,seguimento,série,airpods,relógio,widget,forma",
    "nl-NL": "herinnering,gewoonte,scan,gezondheid,lichaam,rug,zorg,wervelkolom,welzijn,tracker,reeks,airpods,horloge,widget,fitness",
    "pl": "przypomnienie,nawyk,skan,zdrowie,ciało,plecy,opieka,kręgosłup,dobrostan,śledzenie,seria,airpods,zegarek,widget,forma",
    "sv": "påminnelse,vana,skanna,hälsa,kropp,rygg,omvårdnad,ryggrad,välmående,spårare,serie,airpods,klocka,widget,form",
    "da": "påmindelse,vane,scan,sundhed,krop,ryg,pleje,rygsøjle,velvære,sporing,serie,airpods,ur,widget,form",
    "no": "påminnelse,vane,skann,helse,kropp,rygg,pleie,ryggrad,velvære,sporing,serie,airpods,klokke,widget,form",
    "fi": "muistutus,tapa,skannaus,terveys,keho,selkä,hoito,selkäranka,hyvinvointi,seuranta,sarja,airpods,kello,widget,kunto",
    "cs": "připomínka,návyk,sken,zdraví,tělo,záda,péče,páteř,blaho,sledování,série,airpods,hodinky,widget,kondice",
    "sk": "pripomienka,návyk,sken,zdravie,telo,chrbát,starostlivosť,chrbtica,blaho,sledovanie,séria,airpods,hodinky,widget,kondícia",
    "hu": "emlékeztető,szokás,szkennelés,egészség,test,hát,gondoskodás,gerinc,jóllét,követés,sorozat,airpods,óra,widget,fittség",
    "ro": "memento,obicei,scan,sănătate,corp,spate,îngrijire,coloană,bunăstare,urmărire,serie,airpods,ceas,widget,formă",
    "hr": "podsjetnik,navika,sken,zdravlje,tijelo,leđa,skrb,kralježnica,blagostanje,praćenje,serija,airpods,sat,widget,kondicija",
    "el": "υπενθύμιση,συνήθεια,σάρωση,υγεία,σώμα,πλάτη,φροντίδα,σπονδυλική,ευεξία,παρακολούθηση,σερί,airpods,ρολόι,widget,φόρμα",
    "tr": "hatırlatıcı,alışkanlık,tarama,sağlık,vücut,sırt,bakım,omurga,esenlik,takip,seri,airpods,saat,widget,form",
    "ru": "напоминание,привычка,скан,здоровье,тело,спина,уход,позвоночник,благополучие,отслеживание,серия,airpods,часы,widget,форма",
    "uk": "нагадування,звичка,скан,здоров'я,тіло,спина,догляд,хребет,благополуччя,відстеження,серія,airpods,годинник,widget,форма",
    "ja": "リマインダー,習慣,スキャン,健康,身体,背中,ケア,脊椎,ウェルネス,トラッカー,連続記録,airpods,ウォッチ,ウィジェット,フィット",
    "ko": "리마인더,습관,스캔,건강,신체,등,케어,척추,웰빙,트래커,연속,airpods,워치,위젯,핏",
    "zh-Hans": "提醒,习惯,扫描,健康,身体,背部,护理,脊柱,康管理,追踪器,连续,airpods,手表,小组件,健身",
    "zh-Hant": "提醒,習慣,掃描,健康,身體,背部,護理,脊柱,健康管理,追蹤器,連續,airpods,手錶,小工具,健身",
    "ar-SA": "تذكير,عادة,مسح,صحة,جسم,ظهر,رعاية,عمود,عافية,متتبع,سلسلة,airpods,ساعة,ودجت,لياقة",
    "he": "תזכורת,הרגל,סריקה,בריאות,גוף,גב,טיפול,עמוד,רווחה,עוקב,רצף,airpods,שעון,ווידג'ט,כושר",
    "hi": "याद,आदत,स्कैन,स्वास्थ्य,शरीर,पीठ,देखभाल,रीढ़,कल्याण,ट्रैकर,लगातार,airpods,घड़ी,विजेट,फिट",
    "th": "แจ้งเตือน,นิสัย,สแกน,สุขภาพ,ร่างกาย,หลัง,การดูแล,กระดูกสันหลัง,สุขภาวะ,ติดตาม,ต่อเนื่อง,airpods,นาฬิกา,วิดเจ็ต,ฟิต",
    "vi": "nhắc nhở,thói quen,quét,sức khỏe,cơ thể,lưng,chăm sóc,cột sống,sức khỏe tốt,theo dõi,chuỗi,airpods,đồng hồ,widget,vừa vặn",
    "id": "pengingat,kebiasaan,scan,kesehatan,tubuh,punggung,perawatan,tulang belakang,kesejahteraan,pelacak,rangkaian,airpods,jam,widget,bug",
    "ms": "peringatan,tabiat,imbas,kesihatan,badan,belakang,penjagaan,tulang belakang,kesejahteraan,penjejak,rangkaian,airpods,jam,widget,kecergasan",
    "bn-BD": "মনে করিয়ে,অভ্যাস,স্ক্যান,স্বাস্থ্য,শরীর,পিঠ,যত্ন,মেরুদণ্ড,কল্যাণ,ট্র্যাকার,ধারাবাহিক,airpods,ঘড়ি,উইজেট,ফিট",
    "gu-IN": "યાદ,આદત,સ્કેન,સ્વાસ્થ્ય,શરીર,પીઠ,સંભાળ,રીંઢ,કલ્યાણ,ટ્રેકર,સતત,airpods,ઘડિયાળ,વિજેટ,ફિટ",
    "kn-IN": "ಜ್ಞಾಪನೆ,ಅಭ್ಯಾಸ,ಸ್ಕ್ಯಾನ್,ಆರೋಗ್ಯ,ದೇಹ,ಬೆನ್ನಿನ,ಆರೈಕೆ,ಮೂಳೆ,ಕ್ಷೇಮ,ಟ್ರ್ಯಾಕರ್,ಸರಣಿ,airpods,ಗಡಿಯಾರ,ವಿಜೆಟ್,ಫಿಟ್",
    "ml-IN": "ഓർമ്മപ്പെടുത്തൽ,ശീലം,സ്കാൻ,ആരോഗ്യം,ശരീരം,പുറം,പരിചരണം,മുതൻ,ക്ഷേമം,ട്രാക്കർ,തുടർച്ച,airpods,വാച്ച്,വിജറ്റ്,ഫിറ്റ്",
    "mr-IN": "आठवण,सवय,स्कॅन,आरोग्य,शरीर,पाठ,काळजी,मणका,कल्याण,ट्रॅकर,सलग,airpods,घड्याळ,विजेट,फिट",
    "or-IN": "ସ୍ମରଣ,ଅଭ୍ୟାସ,ସ୍କାନ୍,ସ୍ୱାସ୍ଥ୍ୟ,ଶରୀର,ପିଠି,ଯତ୍ନ,ମେରୁଦଣ୍ଡ,ମଙ୍ଗଳ,ଟ୍ରାକର,ଧାରାବାହିକ,airpods,ଘଣ୍ଟା,ୱିଜେଟ,ଫିଟ୍",
    "pa-IN": "ਯਾਦ,ਆਦਤ,ਸਕੈਨ,ਸਿਹਤ,ਸਰੀਰ,ਪਿੱਠ,ਦੇਖਭਾਲ,ਰੀੜ੍ਹ,ਭਲਾਈ,ਟ੍ਰੈਕਰ,ਲਗਾਤਾਰ,airpods,ਘੜੀ,ਵਿਜੇਟ,ਫਿਟ",
    "ta-IN": "நினைவூட்டல்,பழக்கம்,ஸ்கேன்,ஆரோக்கியம்,உடல்,முதுகு,கவனிப்பு,முதுகெலும்பு,நல்வாழ்வு,டிராக்கர்,தொடர்,airpods,கடிகாரம்,விட்ஜெட்,ஃபிட்",
    "te-IN": "రిమైండర్,అలవాటు,స్కాన్,ఆరోగ్యం,శరీరం,వెనుక,సంరక్షణ,వెన్నెముక,శ్రేయస్సు,ట్రాకర్,వరుస,airpods,గడియారం,విడ్జెట్,ఫిట్",
    "ur-PK": "یاددہانی,عادت,اسکین,صحت,جسم,پیٹھ,دیکھ بھال,ریڑھ,بہبود,ٹریکر,تسلسل,airpods,گھڑی,وجیٹ,فٹ",
    "sl-SI": "opomnik,navada,skeniranje,zdravje,telo,hrbet,nega,hrbtenica,blaginja,sledilnik,serija,airpods,ura,widget,fit",
}

SUBTITLES: dict[str, str] = {
    "en-US": "Neck, desk & slouch coach",
    "en-GB": "Neck, desk & slouch coach",
    "en-AU": "Neck, desk & slouch coach",
    "en-CA": "Neck, desk & slouch coach",
    "de-DE": "Nacken- & Schreibtisch-Coach",
    "fr-FR": "Nuque, bureau & posture",
    "fr-CA": "Nuque, bureau & posture",
    "es-ES": "Cuello, escritorio y postura",
    "es-MX": "Cuello, escritorio y postura",
    "ca": "Coll, escriptori i postura",
    "it": "Collo, scrivania e postura",
    "pt-BR": "Pescoço, mesa e postura",
    "pt-PT": "Pescoço, secretária e postura",
    "nl-NL": "Nek, bureau & houding",
    "pl": "Szyja, biurko i postawa",
    "ja": "首・デスク・姿勢コーチ",
    "ko": "목·책상·자세 코치",
    "zh-Hans": "颈椎办公姿势教练",
    "zh-Hant": "頸椎辦公姿勢教練",
    "sv": "Nacke, skrivbord & hållning",
    "da": "Nakke, skrivebord & holdning",
    "no": "Nakke, skrivebord & holdning",
    "fi": "Niska, työpöytä & asento",
    "ru": "Шея, стол и осанка",
    "uk": "Шия, стіл і постава",
    "ar-SA": "تدريب الرقبة والمكتب",
    "he": "מאמן צוואר ושולחן",
    "hi": "गर्दन, डेस्क व पोश्चर",
    "th": "โค้ชคอ โต๊ะ ท่านั่ง",
    "vi": "Huấn luyện cổ & bàn",
    "id": "Pelatih leher & meja",
    "tr": "Boyun, masa ve duruş",
}


def indexed_terms(name: str, subtitle: str) -> set[str]:
    text = f"{name} {subtitle}".lower()
    terms: set[str] = set()
    for w in re.findall(r"[a-z0-9]+", text, flags=re.I):
        if len(w) >= 2:
            terms.add(w)
    return terms


def dedupe_keywords(name: str, subtitle: str, keywords_csv: str) -> str:
    indexed = indexed_terms(name, subtitle)
    kept: list[str] = []
    for raw in keywords_csv.replace(" ", "").split(","):
        kw = raw.strip().lower()
        if not kw:
            continue
        if kw in indexed:
            continue
        if any(kw == t or (len(kw) >= 4 and kw in t) or (len(t) >= 4 and t in kw) for t in indexed):
            continue
        kept.append(kw)
    return ",".join(kept)


def trim_keywords(s: str, limit: int = 100) -> str:
    s = s.replace(" ", "")
    if len(s) <= limit:
        return s
    parts = s.split(",")
    while parts and len(",".join(parts)) > limit:
        parts.pop()
    return ",".join(parts)


def trim_subtitle(s: str, limit: int = 30) -> str:
    return s[:limit] if len(s) > limit else s


def main() -> None:
    report: dict[str, dict] = {}
    for loc_dir in sorted(META.iterdir()):
        if not loc_dir.is_dir() or loc_dir.name == "review_information":
            continue
        loc = loc_dir.name
        if loc not in KEYWORDS:
            continue
        kw_path = loc_dir / "keywords.txt"
        sub_path = loc_dir / "subtitle.txt"
        old_kw = kw_path.read_text(encoding="utf-8").strip() if kw_path.exists() else ""
        old_sub = sub_path.read_text(encoding="utf-8").strip() if sub_path.exists() else ""
        name = (loc_dir / "name.txt").read_text(encoding="utf-8").strip() if (loc_dir / "name.txt").exists() else ""
        sub_for_dedupe = SUBTITLES.get(loc, old_sub)
        raw_kw = KEYWORDS[loc]
        new_kw = trim_keywords(dedupe_keywords(name, sub_for_dedupe, raw_kw))
        kw_path.write_text(new_kw + "\n", encoding="utf-8")
        new_sub = old_sub
        if loc in SUBTITLES:
            new_sub = trim_subtitle(SUBTITLES[loc])
            sub_path.write_text(new_sub + "\n", encoding="utf-8")
        report[loc] = {
            "keywords": {"old": old_kw, "new": new_kw, "len": len(new_kw)},
            "subtitle": {"old": old_sub, "new": new_sub} if loc in SUBTITLES else {},
        }
    out = ROOT / "scripts" / "aso-locale-optimization-report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"Updated {len(report)} locales → {out}")


if __name__ == "__main__":
    main()
