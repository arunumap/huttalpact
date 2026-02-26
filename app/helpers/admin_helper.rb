module AdminHelper
  def admin_sidebar_link_to(text, path)
    active = current_page?(path)
    classes = if active
      "block rounded-md bg-slate-700 px-3 py-2 text-sm font-medium text-white"
    else
      "block rounded-md px-3 py-2 text-sm font-medium text-slate-300 hover:bg-slate-700 hover:text-white"
    end

    link_to text, path, class: classes
  end
end
