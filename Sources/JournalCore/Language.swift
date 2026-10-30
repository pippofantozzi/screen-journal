import Foundation

/// The language the app speaks to her. English phrases are the keys; a phrase with no translation stays English.
/// The journal itself (task kinds, labels, the guide for Claude) always stays in English.
public enum Language: String, CaseIterable, Sendable {
    case portuguese = "pt-BR"
    case english = "en"

    public static let `default` = Language.portuguese

    /// In its own language, so she can find hers whichever one is on.
    public var name: String {
        switch self {
        case .portuguese: "Português (Brasil)"
        case .english: "English"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    public func callAsFunction(_ english: String) -> String {
        switch self {
        case .portuguese: Self.portuguesePhrases[english] ?? english
        case .english: english
        }
    }

    /// Fills each `%@` in order.
    public func callAsFunction(_ english: String, _ blanks: String...) -> String {
        String(format: self(english), locale: locale, arguments: blanks)
    }

    /// A suggested kind's name in this language; her own kinds read as she typed them.
    public func name(ofKind kind: String) -> String {
        switch self {
        case .portuguese: Self.portugueseKinds[kind]?.name ?? kind
        case .english: kind
        }
    }

    public func meaning(of kind: TaskKind) -> String {
        switch self {
        case .portuguese: Self.portugueseKinds[kind.name]?.meaning ?? kind.description
        case .english: kind.description
        }
    }

    static let portugueseKinds: [String: (name: String, meaning: String)] = [
        "design": ("design", "design visual, imagens, vídeo, layouts"),
        "content": ("conteúdo", "escrever ou editar posts, legendas, documentos, textos"),
        "planning": ("planejamento", "planos, calendários, briefings, decidir o que fazer"),
        "meeting": ("reunião", "uma chamada de vídeo ou reunião"),
        "communication": ("comunicação", "conversas e e-mails com pessoas"),
        "outreach": ("prospecção", "prospectar, vender, postar ou responder ao público"),
        "research": ("pesquisa", "ler, buscar, aprender para uma tarefa"),
        "admin": ("administrativo", "contas, ajustes e painéis de qualquer ferramenta, permissões, formulários, arquivos, pagamentos"),
        "building": ("tecnologia", "escrever código, ou dirigir agentes de código num terminal ou editor"),
        "leisure": ("lazer", "entretenimento, navegação pessoal"),
        "other": ("outro", "qualquer coisa que não cabe nos outros"),
    ]

    static let portuguesePhrases: [String: String] = [
        // Menu
        "Starting…": "Iniciando…",
        "Recording · %@ today": "Gravando · %@ hoje",
        "Recording · %@ today · %@": "Gravando · %@ hoje · %@",
        "1 moment": "1 momento",
        "%@ moments": "%@ momentos",
        "Paused": "Pausado",
        "Paused until %@": "Pausado até %@",
        "Resting while you're away": "Descansando enquanto você está fora",
        "Needs Screen Recording access": "Precisa de acesso à Gravação de Tela",
        "Can't capture right now": "Não consegue capturar agora",
        "Turn Screen Access Back On…": "Reativar o Acesso à Tela…",
        "Pause": "Pausar",
        "For 15 Minutes": "Por 15 minutos",
        "For 1 Hour": "Por 1 hora",
        "Until I Resume": "Até eu retomar",
        "Resume": "Retomar",
        "Note This Moment…": "Anotar este momento…",
        "Export WhatsApp Chat…": "Exportar conversa do WhatsApp…",
        "Your Week…": "Sua semana…",
        "Settings…": "Ajustes…",
        "Quit Screen Journal": "Sair do Screen Journal",

        // Window titles
        "Welcome": "Boas-vindas",
        "How Screen Journal Works": "Como o Screen Journal funciona",
        "Your Week": "Sua semana",
        "Screen Journal Settings": "Ajustes do Screen Journal",
        "Note this moment": "Anotar este momento",

        // Settings
        "Take a snapshot every": "Tirar uma foto da tela a cada",
        "%@ seconds": "%@ segundos",
        "Keep the last %@ days": "Manter os últimos %@ dias",
        "Capture": "Captura",
        "Press %@ in any app to note what's going on.": "Pressione %@ em qualquer app para anotar o que está acontecendo.",
        "Another app uses %@; note moments from the menu instead.": "Outro app já usa %@; anote momentos pelo menu.",
        "What you do": "O que você faz",
        "I do marketing for clients, so Instagram is usually work.": "Faço marketing para clientes, então Instagram geralmente é trabalho.",
        "Kinds of task": "Tipos de tarefa",
        "Add your own, then press Return": "Adicione um tipo seu e pressione Return",
        "Edit, then press Return": "Edite e pressione Return",
        "Delete %@": "Apagar %@",
        "Your work": "Seu trabalho",
        "Helps tell your work from the rest, and sort it. Pick only the kinds that fit your work: the fewer, the sharper the sorting. Anything that fits none goes under “other”. Point at a kind to see what it covers.":
            "Ajuda a separar seu trabalho do resto e a organizá-lo. Escolha só os tipos que combinam com o seu trabalho: quanto menos, mais precisa a organização. O que não couber em nenhum vai para “outro”. Aponte para um tipo para ver o que ele abrange.",
        "None picked yet, so every suggestion is used.": "Nenhum escolhido ainda, então todas as sugestões são usadas.",
        "Suggestions: click to add": "Sugestões: clique para adicionar",
        "Add %@": "Adicionar %@",
        "AI Gateway key": "Chave do AI Gateway",
        "Saved": "Salva",
        "Works": "Funciona",
        "Check": "Testar",
        "Disconnect": "Desconectar",
        "Save": "Salvar",
        "The gateway refused this key.": "O gateway recusou esta chave.",
        "Send screenshots too": "Enviar capturas de tela também",
        "Journal": "Diário",
        "Dictation": "Ditado",
        "General": "Geral",
        "AI": "IA",
        "Shortcut": "Atalho",
        "Off": "Desligado",
        "Right %@": "%@ da direita",
        "Write": "Escrever",
        "Edit": "Editar",
        "speak": "fale",
        "highlight": "selecione",
        "say how": "diga como",
        "Words": "Palavras",
        "Language": "Idioma",
        "Portuguese": "Português",
        "English": "Inglês",
        "Automatic": "Automático",
        "Add a name or term, then press Return": "Adicione um nome ou termo e pressione Return",
        "Accessibility": "Acessibilidade",
        "Microphone": "Microfone",
        "Allow…": "Permitir…",

        // Dictation
        "Connect AI in Settings → General.": "Conecte a IA em Ajustes → Geral.",
        "Allow the microphone in Settings → Dictation.": "Permita o microfone em Ajustes → Ditado.",
        "Didn't catch that.": "Não entendi.",
        "Didn't hear anything. Check the microphone in Settings → Dictation.": "Não ouvi nada. Confira o microfone em Ajustes → Ditado.",
        "The gateway refused the AI key.": "O gateway recusou a chave da IA.",
        "No internet connection.": "Sem conexão com a internet.",
        "Couldn't transcribe. Try again.": "Não deu para transcrever. Tente de novo.",
        "No microphone.": "Nenhum microfone.",
        "How It Works": "Como funciona",
        "Open Journal Folder": "Abrir pasta do diário",
        "Check for Updates": "Buscar atualizações",

        // Your week
        "%@ tracked": "%@ registrados",
        "Nothing tracked": "Nada registrado",
        "The week before": "Semana anterior",
        "The week after": "Semana seguinte",
        "Nothing sorted yet this week. Once your sessions are sorted, you'll see here where your time went.":
            "Nada organizado ainda nesta semana. Quando suas sessões forem organizadas, você verá aqui para onde foi seu tempo.",
        "Screen Journal wasn't recording these days.": "O Screen Journal não estava gravando nesses dias.",
        "Not sorted yet: %@. It shows up here once it's sorted.": "Ainda não organizado: %@. Aparece aqui quando for organizado.",
        "Where Claude could help most": "Onde o Claude mais poderia ajudar",
        "Claude could probably take over": "O Claude provavelmente poderia assumir",
        "The rest": "O resto",
        "See the screenshots": "Ver as capturas",
        "Click a task to see its screenshots": "Clique numa tarefa para ver as capturas",
        "All tasks": "Todas as tarefas",
        "All": "Tudo",
        "Claude could take over": "O Claude poderia assumir",
        "%@ sessions · %@": "%@ sessões · %@",
        "Nothing here with these filters.": "Nada aqui com esses filtros.",
        "No screenshot kept": "Captura não guardada",
        "Open it larger": "Abrir maior",
        "Task": "Tarefa",
        "Show": "Mostrar",
        "%@: %@, of which Claude could probably take over %@": "%@: %@, dos quais o Claude provavelmente poderia assumir %@",

        // Note
        "What's going on right now?": "O que está acontecendo agora?",
        "e.g. copying invoices into the spreadsheet again": "ex.: copiando notas fiscais para a planilha de novo",
        "Cancel": "Cancelar",
        "Save Note": "Salvar nota",

        // Guide
        "Back": "Voltar",
        "Next": "Próximo",
        "Done": "Pronto",
        "Copy": "Copiar",
        "Copied": "Copiado",
        "What Screen Journal does": "O que o Screen Journal faz",
        "Every 10 seconds it looks at your screen and saves a snapshot, but only if something changed.":
            "A cada 10 segundos ele olha sua tela e salva uma foto, mas só se algo mudou.",
        "It reads the text on screen and notes which app and window you're in.":
            "Ele lê o texto na tela e anota em qual app e janela você está.",
        "Everything stays in the ScreenJournal folder on this Mac. Only when AI categorization is connected are short excerpts sent, to sort your sessions.":
            "Tudo fica na pasta ScreenJournal deste Mac. Só quando a categorização por IA está conectada, trechos curtos são enviados para organizar suas sessões.",
        "The menu bar icon": "O ícone na barra de menus",
        "Aperture: journaling.": "Obturador: registrando.",
        "Moon: resting while you're away or the screen is locked.": "Lua: descansando enquanto você está fora ou a tela está bloqueada.",
        "Pause: you paused it.": "Pausa: você pausou.",
        "Warning: it needs your help. Click it and choose Turn Screen Access Back On.":
            "Alerta: ele precisa da sua ajuda. Clique e escolha Reativar o Acesso à Tela.",
        "Pause any time": "Pause quando quiser",
        "Menu → Pause → 15 minutes, 1 hour, or until you resume.": "Menu → Pausar → 15 minutos, 1 hora ou até você retomar.",
        "Use it for anything private: personal chats, health, shopping, surprises 🎁.":
            "Use para qualquer coisa privada: conversas pessoais, saúde, compras, surpresas 🎁.",
        "Timed pauses resume by themselves. Otherwise choose Resume.": "Pausas com tempo retomam sozinhas. Senão, escolha Retomar.",
        "Leave a note": "Deixe uma nota",
        "When something feels tedious or repetitive, press ⌥Space in any app.":
            "Quando algo parecer chato ou repetitivo, pressione ⌥Space em qualquer app.",
        "A few words is plenty: \"copying orders into the sheet again\".": "Poucas palavras bastam: \"copiando pedidos para a planilha de novo\".",
        "Notes are the most useful clue Claude gets. Ten notes in a week beats none.":
            "As notas são a pista mais útil que o Claude recebe. Dez notas numa semana valem mais que nenhuma.",
        "What's never saved": "O que nunca é salvo",
        "Password managers are blanked out, and nothing is saved while one is in front.":
            "Gerenciadores de senhas ficam em branco, e nada é salvo enquanto um deles está na frente.",
        "Nothing is saved while the screen is locked or you've been away for 2 minutes.":
            "Nada é salvo enquanto a tela está bloqueada ou quando você fica 2 minutos fora.",
        "Days older than 30 are deleted automatically. You can change that in Settings.":
            "Dias com mais de 30 dias são apagados automaticamente. Você pode mudar isso nos Ajustes.",
        "After a week: ask Claude": "Depois de uma semana: pergunte ao Claude",
        "Open Terminal, paste the line below, and press Return.": "Abra o Terminal, cole a linha abaixo e pressione Return.",
        "Then type: find what I should automate.": "Depois digite: descubra o que eu deveria automatizar.",
        "Claude reads your journal, suggests automations, and can build the ones you pick.":
            "O Claude lê seu diário, sugere automações e pode criar as que você escolher.",
        "If something seems off": "Se algo parecer estranho",
        "macOS sometimes asks again for screen permission. Just allow it.": "Às vezes o macOS pede de novo a permissão de tela. É só permitir.",
        "Updates install by themselves. Settings → General → Check for Updates if you're curious.":
            "As atualizações se instalam sozinhas. Ajustes → Geral → Buscar atualizações, se tiver curiosidade.",
        "Settings → Open Journal Folder shows everything that was saved.": "Ajustes → Abrir pasta do diário mostra tudo o que foi salvo.",
        "Still stuck? Ask Filippo. 💌": "Ainda com dúvida? Pergunte ao Filippo. 💌",

        // WhatsApp export
        "Export WhatsApp chat": "Exportar conversa do WhatsApp",
        "Chat": "Conversa",
        "Last": "Últimas",
        "messages": "mensagens",
        "Export": "Exportar",
        "Saving…": "Salvando…",
        "Saved. %@ media files were never downloaded to this Mac and are marked omitted.":
            "Salvo. %@ arquivos de mídia nunca foram baixados neste Mac e aparecem como omitidos.",
        "%@ voice notes couldn't be transcribed.": "%@ áudios não puderam ser transcritos.",
        "WhatsApp for Mac isn't set up on this Mac.": "O WhatsApp para Mac não está configurado neste Mac.",
        "Can't read WhatsApp's messages: %@": "Não foi possível ler as mensagens do WhatsApp: %@",
        "Couldn't save the zip: %@": "Não foi possível salvar o zip: %@",

        // Onboarding
        "Hi! Let's learn how you work": "Oi! Vamos entender como você trabalha",
        "Screen Journal quietly takes a snapshot of your screen every few seconds, but only when something changed. Everything stays on this Mac. After a week or two, Claude can read it and suggest ways to automate the boring parts.":
            "O Screen Journal tira uma foto da sua tela a cada poucos segundos, em silêncio, mas só quando algo mudou. Tudo fica neste Mac. Depois de uma ou duas semanas, o Claude pode ler e sugerir formas de automatizar as partes chatas.",
        "Get Started": "Começar",
        "Allow screen snapshots": "Permitir fotos da tela",
        "macOS will ask you to turn on Screen Journal under **Screen & System Audio Recording**. Flip the switch, then come back here.":
            "O macOS vai pedir para você ativar o Screen Journal em **Gravação de Tela e Áudio do Sistema**. Ative a chave e volte aqui.",
        "Access granted": "Acesso permitido",
        "Open System Settings": "Abrir Ajustes do Sistema",
        "Open System Settings Again": "Abrir Ajustes do Sistema de novo",
        "Already switched it on? Restart Screen Journal": "Já ativou? Reiniciar o Screen Journal",
        "Know which chat and which page": "Saber qual conversa e qual página",
        "Turn on Screen Journal under **Accessibility**, so the journal also notes which chat, website or folder is open.":
            "Ative o Screen Journal em **Acessibilidade**, para o diário anotar também qual conversa, site ou pasta está aberto.",
        "Turned on": "Ativado",
        "Skip for Now": "Pular por enquanto",
        "You're all set": "Tudo pronto",
        "Look for the little aperture in your menu bar. Press ⌥Space in any app to jot down what's going on, especially when something feels tedious. It starts by itself when you log in; pause it from the menu any time.":
            "Procure o pequeno obturador na barra de menus. Pressione ⌥Space em qualquer app para anotar o que está acontecendo, principalmente quando algo parecer chato. Ele abre sozinho quando você liga o Mac; pause pelo menu quando quiser.",
        "macOS didn't let it open at login: move the app to Applications and open it again.":
            "O macOS não deixou ele abrir sozinho: mova o app para Aplicativos e abra de novo.",
        "Start Journaling": "Começar o diário",
    ]
}
